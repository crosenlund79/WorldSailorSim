# The GDScript Guide (English)

A friendly map of every script in Little Captain's Hat: what each one does,
what it works with, when it runs and what might change if you change it.
There is one entry per `.gd` file, grouped by where the file lives. The
Danish edition is [GDSCRIPT_GUIDE_DA.md](GDSCRIPT_GUIDE_DA.md); the
developer reference (dependencies, signals, invariants, tests) is
[GDSCRIPT_ARCHITECTURE.md](GDSCRIPT_ARCHITECTURE.md).

**The code is the authority.** If an entry here disagrees with the script,
the script is right and the entry needs a review. The checker
`python tools/docs/check_gdscript_guides.py` tells you which entries are
missing or may be out of date (see [How the guides stay current](#how-the-guides-stay-current)).

A few words you will meet:

- **Script**: a `.gd` file of GDScript code. Most attach to a **node** (a
  thing in a Godot scene: a label, a boat, a button) and give it behaviour.
- **Scene**: a `.tscn` file, a ready-made arrangement of nodes (a boat's
  cabin, a menu).
- **Autoload**: a script Godot starts once when the game starts and keeps
  running the whole time, reachable by name from anywhere (`GameSession`,
  `Simulation`, …).
- **Signal**: a message a script sends ("the boat arrived"); other scripts
  can listen for it without the sender knowing who they are.
- **Resource**: a data file Godot can load (`.tres`), such as a harbour or a boat's
  performance figures.
- **State**: the facts the game remembers (where the boat is, the time, your
  money). Saved games are made of it.

## A tour of the game

### How the game starts

Godot opens `src/app/app.tscn`, the **application shell** (`App`,
`src/app/app.gd`). Eight autoloads are already running: settings, audio,
the game session, the simulation, saves, the diagnostic log, the interface
theme and the music director. The shell shows the loading screen (it
prepares the world's sea chart once), then the main menu. On the very first
launch it asks for the language. **New Game** asks for a companion (cat or
dog) and starts a fresh session in Copenhagen aboard the Arctic Wanderer 26.

### Screens, menus and interactions

Exactly one **screen** is shown at a time (main menu, the deck, the cabin,
the chart or the dream map), swapped with a fade by `SceneRouter`. Menus
and dialogs open on top in a **modal stack** (`ModalStack`). While a menu is
open the game world pauses. The heads-up display (`Hud`) sits above the
world. On a boat, the player walks with WASD. Standing near a station (the
helm, the chart table, the stove, the rod…) and pressing **E** asks the boat
area (`BoatArea`) to do something. The boat area passes the request up to
`App`, and `App` opens the right menu or asks the game to act. **Q** opens
the action wheel, a short list of what you can do right now.

### Where the player and the boat live

Everything the game remembers is plain data in `SessionState`
(`src/core/session_state.gd`), owned by the `GameSession` autoload. Only
`GameSession` changes it: scenes and menus *ask* (`GameSession.depart()`,
`GameSession.buy_decor(...)`), and `GameSession` checks the rules, changes
the data and sends a signal so the screens can update. The boat, the
voyage, the anchor, the fish in the cool box, the hat, the companion, your
money and renown, and each boat's care and cabin all live there.

### How time and weather move

Game time runs only through the `Simulation` autoload. Every frame it moves
the clock forward (faster at 5× or 20×) and moves the boat along its course.
On a fixed grid of moments (every 5 game minutes) it asks the weather
(`WeatherModel`, `WindField`) what the wind is doing, decides sail or engine
(`PropulsionController`), checks the route ahead for bad weather, the
anchor, the stores, traffic and the radio. Because the weather is
calculated from the time and place only, it is the same whether you sail at
1×, sleep through it or load a saved game.

### Worldwide navigation

Harbours are data (`PortCatalog`, one `PortData` per harbour). The sea
chart of the world is prebuilt into a navigation grid (`NavGrid`), and
`SeaRouter` finds a route along it that keeps off the land, through canals
(Kiel, Suez, Panama) where they are open. The chart table (`WorldMap`) shows
it, lets you place waypoints and anchorages, and plans the voyage.
`PlannedRoute` is a plan made in harbour. `Voyage` is the trip once you have
cast off.

### Long Passage

On a long voyage you can let hours pass every second. `Simulation` runs the
same steps faster (`passage_rate`) and stops by itself when something needs
you: weather ahead, a fish on the line, the anchorage reached, a ship on a
collision course, a call on the radio, arrival. The voyage map (`VoyageMap`)
shows the trip while it runs.

### Saving and loading

`SaveManager` writes the whole `SessionState` as JSON into a save slot and
reads it back, checking everything and upgrading older saves (migrations).
The save format is version 12. Newer parts (the anchor's alarm level, the
VHF stand-by, the cabin things) are optional, so older saves still load.
Settings, including the language, are saved separately (`SettingsManager`)
and never in a game.

### English and Danish

The game speaks English or Dansk (I019). Text is looked up in a catalogue
(`locale/da.po`) through small helpers in `Loc` (`src/core/loc.gd`): a
sentence is translated first, then the numbers go in, and numbers, dates,
money and compass points take each language's form. Buttons and labels that
show a whole sentence are translated by Godot itself. The language is
chosen at the first launch (`LanguagePicker`) or in Settings.

### Traffic, radar and the VHF (I019)

Other ships are made up on the spot by `TrafficModel` from the place and
time, so the same ships are there after a load. `Simulation` works out
whether any will pass close (closest point of approach). A real risk is
announced once, and it wakes you and stops Long Passage. The radar on deck
(`RadarPanel`) shows the ships. Now and then a call comes in on the radio
(`VhfRadio`, `VhfDialog`): a yacht asking you to stand by, or a fishing boat
wanting the forecast. Answering is optional, and the thanks are paid once.

### Shops and a boat of your own (I020)

The fishmonger, the chandlery and the sailmaker (`HarbourTrades`) are found
in harbours whose data allows them, through the grocery store and the
boatyard. Every purchase goes through `GameSession` and is whole or
nothing. What you own for your cabins and each boat's sailcloth live in
`HomeState`. The cabin things are drawn by `CabinDecor` in places the cabin
itself has room for, never over a station.

## How the guides stay current

Each script has one entry in each of the three guides, under a heading
like ``### `src/core/loc.gd` ``. When a script is added, removed or
changed, run:

```
python tools/docs/check_gdscript_guides.py
```

It lists entries that are missing, duplicated or left over, and scripts
that changed since their entries were last reviewed. After reading the
script and updating its entries, record the review:

```
python tools/docs/check_gdscript_guides.py --acknowledge src/core/loc.gd --note "reviewed after the plural helper"
```

The rules are in [CAPTAINS_ORDERS.md](../../CAPTAINS_ORDERS.md) (Working rules).


## Application shell, core state and services

### `src/app/app.gd`

**Purpose:** The game's main "conductor": it connects the menus, the screens and the game systems so they all work together.
- **What it does:** Shows the main menu, starts and loads games, opens every window (pause menu, sleep, fishing rod, anchor, boatyard, shops, Captain's Log and more) and turns game events into short on-screen messages and sounds. It is the one place that handles Esc and the hotkeys (F5 quicksave, F9 quickload, H hat, L log, R reel in), so two windows never react to the same key press. On arrival (I021) it shows the arrival card: the harbour's picture, "Arrived in …" and one sentence about the place. Since I022 it asks before buying a boat at the boatyard, starts new games at the chosen difficulty and opens the Difficulty dialog from the pause menu. I022: hours-long tasks aboard (remote work, a postcard, a session on the little game) pass on the one clock through `pass_time`: a fade to black, the simulation run once while the clock counts, a line if something interrupted it, and back in at ×1; the cabin's Q wheel offers Write a postcard and Work on your little game. I022 Academy: it holds the Academy card on its own layer, offers the First Voyage once on the first new game on this computer, and opens the Captain's Handbook with F1 or from the pause menu. Steady Hands: each button gets its click sound once, also when it is moved to another parent. Golden Harbours: the first arrival in a harbour that has a picture shows the Golden Harbour Moment (the harbour's picture lit for the hour, with the Captain's Log line on it) instead of the small card and a separate Log message; a known harbour keeps the small card. Renown messages now show the milestone names in the chosen language.
- **Works with:** `GameSession`, `Simulation`, `SaveManager`, `SceneRouter`, `Hud`, `ModalStack`, `Toasts`, `AudioManager`, `WeatherAudio`, `SessionLog`.
- **Keeps:** Only screen bookkeeping: whether the rescue report is open, a VHF call or anchorage question waiting to be shown, the seconds left before a hooked fish gets away, and when the companion next follows you between cabin and deck. The game itself lives in `GameSession`.
- **When it runs:** Always: it is the main scene that starts with the game.
- **If you change it:** Almost every flow can be affected: which windows open where, when the game pauses behind a menu, what the player is told after sleeping or arriving, the engine sound, quicksave rules.

### `src/app/game_version.gd`

**Purpose:** Holds the game's version number in one place.
- **What it does:** Gives the version shown to players (for example "0.108a"), a numbers-only form for tools, and the short code of the exact build (commit) when it can be found.
- **Works with:** `SessionLog` (writes the version at start-up), the main menu (shows it), `tools/write_build_info.py` (writes `build_info.json`).
- **Keeps:** The build's commit code, read once and remembered.
- **When it runs:** Whenever something asks for the version (start-up log, main menu).
- **If you change it:** You must also change the version in the project settings; a test checks that the two match. Saves record the game version.

### `src/app/scene_router.gd`

**Purpose:** Swaps the one visible screen (main menu, cabin, deck, chart) with a short fade to black.
- **What it does:** Removes the old screen, creates the new one and fades back in. Only one screen exists at a time, so the player or the boat can never be duplicated.
- **Works with:** `App` (asks for every screen change); the screens themselves.
- **Keeps:** The current screen and whether a change is in progress ("busy").
- **When it runs:** Every time the screen changes.
- **If you change it:** Screen changes, fade timing and the "busy" check that many windows wait for.

### `src/core/academy.gd`

**Purpose:** The Captain's Academy's content and progress (I022): the Captain's Handbook, the First Voyage and the tips.
- **What it does:** Reads `data/academy/academy.json`: the Handbook's chapters and pages, the eight First Voyage steps and the tips. Keys are never written in the texts; `{interact}` and the like are filled in from the game's own key bindings as the keyboard labels them, so no text can name a wrong key. It searches the pages in the current language, and keeps the progress (First Voyage offered, begun, skipped or done; the step reached; the tips already shown) in the settings of this computer.
- **Works with:** `SettingsManager` (the progress), `AcademyGuide`, `HandbookMenu`, `App`, `Loc`.
- **Keeps:** The data file, read once.
- **When it runs:** When a page, step or tip is shown, and when the progress changes.
- **If you change it:** Add new texts to the data file with `{action}` placeholders; `test_academy` fails on an unknown placeholder or a missing Danish text.

### `src/core/anchor_state.gd`

**Purpose:** The record of the anchor: whether the boat lies at anchor, where, and how well it holds.
- **What it does:** Stores the anchor's position, chain length (scope: 3, 5 or 7 times the depth), how well it was set, its holding (well, fair, poor, dragging), the anchor alarm, the quiet "life at anchor" moments already seen, and which anchor is down (normal or Magic Anchor). It can copy itself and turn itself into save data and back.
- **Works with:** `SessionState` (holds it), `GameSession` (the only code that changes it), `SaveManager`.
- **Keeps:** All the anchor facts listed above.
- **When it runs:** Whenever the anchor is used, checked, saved or loaded.
- **If you change it:** Saves (anchor part), the anchor alarm, dragging, and which quiet moments at anchor repeat after loading.

### `src/core/boat_care_state.gd`

**Purpose:** The care record of one boat: everyday wear, fitted equipment and service history.
- **What it does:** Remembers when the bottom was last cleaned, how worn the rigging is (0–100), engine hours since the last service, which equipment upgrades are fitted, and the last 12 services.
- **Works with:** `SessionState` (one record per boat), `GameSession` (changes it), `BoatCare` (works out what the wear means), `SaveManager`.
- **Keeps:** The facts listed above, per boat.
- **When it runs:** While sailing (wear grows) and at the boatyard (services, upgrades); when saving and loading.
- **If you change it:** Boat speed and weather damage from wear, the boatyard screens, and the "boat_care" part of saves.

### `src/core/captains_log.gd`

**Purpose:** The Captain's Log: your sailing history.
- **What it does:** Keeps the totals (miles sailed, voyages completed, arrivals), the longest passage, every harbour visited, and the last 50 voyages. It records a voyage when it ends, by arrival or by rescue.
- **Works with:** `GameSession` (the only writer), `ObjectiveCatalog` (reads it to award renown), the Captain's Log menu, `SaveManager`.
- **Keeps:** The statistics, visited harbours and recent voyages.
- **When it runs:** When a voyage ends; when the log is shown, saved or loaded.
- **If you change it:** The Captain's Log screen, achievements and renown that depend on miles or harbours, and the "log" part of saves.

### `src/core/difficulty.gd`

**Purpose:** The three difficulty levels: Relaxed, Standard and Seasoned Captain (I022).
- **What it does:** Reads `data/progression/difficulty.json` and gives the factors of the level being played: starting money, how fast food and water are used, wear, weather damage, harbour costs and the rescue fee. Standard is 1.0 everywhere, the game as designed; the weather itself is the same at every level. It also gives each level's name and description in the current language.
- **Works with:** `GameSession` (the level of the game), `SessionState` (starting money), the places that use the factors (`GameSession` provisions, wear, boat care quotes and rescue; `Simulation` weather damage), `DifficultyPicker`.
- **Keeps:** The levels from the data file, read once.
- **When it runs:** Whenever one of those numbers is used.
- **If you change it:** Every game's balance changes for the levels you edit; Standard should stay 1.0.

### `src/core/fishing_state.gd`

**Purpose:** Everything about fishing aboard that should be remembered.
- **What it does:** Records the rod and lures, whether the line is out (and trolling or still), the fish in the cool box, catch records per species, the five-fish trophy board, keep preferences (which fish to keep) and whether fast time stops for every bite. Every fish gets its own number so it can only be kept, released, sold or cooked once.
- **Works with:** `SessionState`, `GameSession` (the only writer), `FishingCatalog`, the fishing menu and trophy board, `SaveManager`.
- **Keeps:** All of the above. A bite in progress is not saved.
- **When it runs:** When fishing, selling or cooking fish; when saving and loading.
- **If you change it:** Fishing, the cool box size, the trophy board, and the "fishing" part of saves.

### `src/core/galley_state.gd`

**Purpose:** The galley record: meals and the coffee mug.
- **What it does:** Remembers when the crew was last given a warm meal (a "well fed" crew eats a little less food until a set time), how many meals were cooked, and where the coffee mug is (in hand, in the holder, on the table).
- **Works with:** `SessionState`, `GameSession`, `SaveManager`.
- **Keeps:** Well-fed time, meal count, last meal, and the mug's place.
- **When it runs:** When cooking, making coffee, saving and loading.
- **If you change it:** How fast food runs out after a meal, the coffee mug, and the "galley" part of saves.

### `src/core/game_session.gd`

**Purpose:** The keeper of the running game: the only place where the game's state is changed.
- **What it does:** Starts, ends and loads games, and offers every game action: planning a course, setting sail, arriving, rescue, money, provisions, boat care, fishing, cooking, the anchor, the captain's hat, companion moves, renown and travel updates. It announces each change with signals (messages other parts of the game listen for) and never touches screens. Since I022 boats are bought (`buy_vessel`, once, at a boatyard, never below zero money) and only boats you own can be sailed; it also keeps the difficulty, which scales food and water use, wear, boat care and provisions prices and the rescue fee. I022 pastimes: it keeps the postcard being made (time spent kept when interrupted, thrown away on request), puts a finished card in the scrapbook with renown the first time for each subject, and counts the little game's sessions for the hours actually worked, with a milestone renown once each and the first sales when it is released.
- **Works with:** `SessionState` (the data it owns), `Simulation` (moves time forward and calls back into it), `SaveManager`, `App`, the HUD and menus, many catalogues (`PortCatalog`, `SeaRouter`, `VesselCatalog`, `ObjectiveCatalog`, `BoatCare`, `FishingCatalog`).
- **Keeps:** The current `SessionState`, whether there are unsaved changes, and a few things that are not saved (a fish on the line, whether the captain is asleep, whether the boat is settled at anchor).
- **When it runs:** Always (an autoload: a script Godot starts automatically and that always exists).
- **If you change it:** Nearly all gameplay rules and what ends up in saves. Change with great care.

### `src/core/hat_state.gd`

**Purpose:** The record of the captain's hat.
- **What it does:** Remembers whether the hat is on its hook, worn, carried under the arm or lost; how much wind strain it has taken; how many hats were lost and bought; and a short history of memorable hat moments for the Captain's Log.
- **Works with:** `SessionState`, `GameSession` (the only writer), `Simulation` (wind checks), `ObjectiveCatalog` (hat achievements), the hat badge and player art.
- **Keeps:** All hat facts above. There is only one hat, and it belongs to the player, not the boat.
- **When it runs:** On deck in wind, when the hat is used or bought, saving and loading.
- **If you change it:** When the hat blows away, hat achievements, and the "hat" part of saves.

### `src/core/home_state.gd`

**Purpose:** "A boat of your own": the cabin decorations you own and each boat's sails.
- **What it does:** Remembers which cabin things you bought, which are shown on each boat, and which sail cloth each boat uses. Unknown items are dropped quietly when loading.
- **Works with:** `SessionState`, `GameSession`, `HarbourTrades` (the list of decor and cloths), the "Make it home" menu and the sailmaker.
- **Keeps:** Owned decor and the per-boat choices.
- **When it runs:** When buying or choosing decor or sails; saving and loading.
- **If you change it:** Cabin decoration, sail colours, and the "home" part of saves (optional, so old saves still load).

### `src/core/loc.gd`

**Purpose:** Small helpers for speaking English or Danish.
- **What it does:** Translates texts, picks singular or plural, gives month and weekday names, and writes numbers the local way (5.5 vs 5,5; 10,000 vs 10.000).
- **Works with:** Godot's translation system and the Danish catalogue `locale/da.po`; used by nearly every script that shows text.
- **Keeps:** Nothing of its own (only a cached pattern for number formatting).
- **When it runs:** Whenever text is shown.
- **If you change it:** Text and numbers everywhere in the game, in both languages.

### `src/core/objective_catalog.gd`

**Purpose:** The list of sailing goals and achievements that earn renown.
- **What it does:** Reads the goals from `data/progression/objectives.json`, adds a few "far horizons" goals for distant harbours, and checks which goals a finished voyage or a hat event has completed. It also knows how many euros a travel update pays per renown point. Secret achievements stay hidden until found.
- **Works with:** `GameSession` (asks it after a voyage or hat event), `CaptainsLog`, `ObjectiveProgress`, `HatState`, `PortCatalog`, the Captain's Log menu.
- **Keeps:** The loaded goals (read-only).
- **When it runs:** When a voyage ends, when the hat is lost or bought, and when the log shows goals.
- **If you change it:** Which achievements exist, how much renown they give, and how much travel updates pay.

### `src/core/objective_progress.gd`

**Purpose:** Your renown and which goals you have completed.
- **What it does:** Keeps lifetime renown (never goes down), renown not yet published, each completed goal and when, the latest rewards, and the travel updates published. It makes sure no voyage is ever paid twice.
- **Works with:** `SessionState`, `GameSession` (the only writer), `ObjectiveCatalog`, the Captain's Log menu, Go Ashore events.
- **Keeps:** All of the above.
- **When it runs:** When renown is earned or published; saving and loading.
- **If you change it:** Renown, travel-update income, and the "progress" part of saves.

### `src/core/pastimes.gd`

**Purpose:** The rules of the captain's two pastimes aboard: Postcards from the Sea and A Game Developer at Sea (I022).
- **What it does:** Reads `data/pastimes/postcards.json` and `data/pastimes/game_dev.json`. For postcards it finds what a card can show from the game's own records (harbours visited, fish caught, the companion, voyages made, the weather met on them, the evening light where the boat is), the captions with the names filled in, the layouts, how long a card takes (two hours) and its renown; each subject earns renown only once. For the little game it gives the title, the milestones, the tasks (2 to 4 hours each), how many points a session earns (double for the wise answer) and the order the answers are shown in.
- **Works with:** `GameSession` (keeps the state and pays the renown), `PastimesState`, `PostcardMenu`, `PostcardView`, `GameDevMenu`, the Captain's Log, fishing records, `PortCatalog`, `Daylight`.
- **Keeps:** Only the two data files, read once.
- **When it runs:** When a pastime menu opens and when a card or session is finished.
- **If you change it:** Change the texts in the data files (they are extracted for translation); keep the subjects tied to real game records so no card shows something that did not happen.

### `src/core/pastimes_state.gd`

**Purpose:** What the save remembers of the pastimes: the scrapbook, a postcard being made, and the little game's progress (I022).
- **What it does:** Holds the postcards made (newest last, at most 40), the card being made with the minutes already spent on it, and the game's points, milestone, sessions, an interrupted session and the devlog. It turns them into save data and back; an older save simply has an empty scrapbook, and broken parts are left out instead of refusing the save.
- **Works with:** `SessionState` (saved as "pastimes"), `GameSession`.
- **Keeps:** `postcards`, `draft`, `game`.
- **When it runs:** On saving, loading and copying the game state.
- **If you change it:** Keep reading lenient; an interrupted card or session must survive a save so it can be finished later.

### `src/core/provisions.gd`

**Purpose:** Provisions: how many days of food and water are aboard.
- **What it does:** Uses up one day of each per 24 game hours (food a little slower when the crew is well fed), restocks, and decides when to warn (low, critical, empty). Running out never hurts anyone; it only stops the next departure.
- **Works with:** `SessionState`, `GameSession`, the provisions locker, grocery store, HUD and cabin graphics.
- **Keeps:** Food days, water days, and the last warning given.
- **When it runs:** Every step of game time, and when shopping or cooking.
- **If you change it:** How long you can sail, the warnings, and the "provisions" part of saves.

### `src/core/session_state.gd`

**Purpose:** The complete saved picture of one game, as plain data.
- **What it does:** Holds everything a save needs (where you are aboard, the clock, the boat and its position, the voyage, money, provisions, condition per boat, the log, renown, the hat, fishing, galley, anchor, boat care, home) and turns it into save data and back, checking every part. Since I022 it also keeps which boats the captain owns and the difficulty; saves from before I022 own every boat and are Standard. I022: it also saves the pastimes (the scrapbook, a card being made, the little game).
- **Works with:** `GameSession` (owns and changes it), `SaveManager` (writes and reads it), all the smaller state records in `src/core/`.
- **Keeps:** The whole game state.
- **When it runs:** At new game, every save and load, and as the data behind all of play.
- **If you change it:** The save format itself. A change here usually needs a new save version and a migration in `SaveManager`.

### `src/core/simulation.gd`

**Purpose:** The game clock and the engine that moves the boat through time.
- **What it does:** Every frame turns real time into game time (1 real second = 1 game minute at 1×) and moves the boat along its course, choosing sail or engine from the wind. It checks the weather, the hat, fish bites, the anchor, traffic and VHF radio calls on a fixed time grid, so the result is the same at any speed, while sleeping or during a Long Passage. Since I022 weather damage is scaled by the difficulty (the weather itself is not). I022: remote work also reports what stopped it early, so the time-passing screen can say so.
- **Works with:** `GameSession` (reads and updates the game), `WeatherModel`, `PropulsionController`, `WeatherDamage`, `HatConfig`, `FishingCatalog`, `TrafficModel`, `VhfRadio`; `App` listens to its warnings.
- **Keeps:** Not saved: the Long Passage speed, a cached arrival estimate, and whether the captain is below deck.
- **When it runs:** Always (an autoload); it stops while the game is paused.
- **If you change it:** Sailing speed, arrival times, weather warnings, damage and rescues, hat losses and bites. Very sensitive.

### `src/core/vessel_condition.gd`

**Purpose:** Names for how healthy a boat is (0–100 %).
- **What it does:** Sorts a condition into Sound, Worn, Damaged or Critical and writes it like "87 % · Sound".
- **Works with:** HUD, boatyard and passage panels, boat damage visuals, `BoatCare`.
- **Keeps:** Nothing of its own; the condition value lives in `SessionState`.
- **When it runs:** Whenever the condition is shown.
- **If you change it:** Labels and the damage look of the boat.

### `src/core/vhf_radio.gd`

**Purpose:** Calls on the VHF radio while sailing.
- **What it does:** Now and then a yacht in trouble asks you to stand by, or a fishing boat asks for the forecast. Whether a call comes is fixed by the voyage and the game's weather seed, so loading or sleeping never brings the same call twice. It also writes what you hear on the radio.
- **Works with:** `Simulation` (asks for calls), `GameSession` (answering and rewards), the VHF dialog.
- **Keeps:** Nothing of its own.
- **When it runs:** While underway, every few hours of game time.
- **If you change it:** How often calls come, how long standing by takes, and the renown and money they give.

### `src/diagnostics/session_log.gd`

**Purpose:** A small technical diary of each run of the game, for finding bugs (not the player's Captain's Log).
- **What it does:** Writes one line per important event (start, screen changes, saves, voyages, the hat, rescues, money, errors) to a file in the user folder. Files are kept small and only the newest 10 are kept.
- **Works with:** `GameSession` signals, `SaveManager`, `App`, `GameVersion`.
- **Keeps:** The open log file and how much has been written.
- **When it runs:** Always (an autoload).
- **If you change it:** Only the diagnostics files; gameplay is not affected.

### `src/persistence/legacy_saves.gd`

**Purpose:** Brings over saves from "Next Harbor", the game's old name.
- **What it does:** Finds old saves in the old folder and, when the player agrees, copies them into free save slots. The old files are never changed, and a slot in use is never overwritten.
- **Works with:** `SaveManager`, `App` and the main menu (the Import button).
- **Keeps:** Nothing of its own (tests can point it at another folder).
- **When it runs:** From the main menu, only when old saves exist.
- **If you change it:** Importing old games.

### `src/persistence/save_manager.gd`

**Purpose:** Saves and loads games.
- **What it does:** Writes 3 save slots and a quicksave as files in the user folder, safely (a temporary file is checked, and the previous save is kept as a backup). On load it checks the file and upgrades older save versions step by step.
- **Works with:** `SessionState`, `App`, the save/load menu, main menu, `LegacySaves`, `SessionLog`.
- **Keeps:** Only the save folder location; the saves are files.
- **When it runs:** Always (an autoload); does work when saving, loading or listing slots.
- **If you change it:** Whether old saves still load. Be very careful.

### `src/settings/settings_manager.gd`

**Purpose:** The player's settings, separate from saved games.
- **What it does:** Keeps and applies volumes, window mode, VSync, interface size, art style, the turning sailing view, flashing and motion options, day/night interface light, language, and the last sleep length. Changes apply at once; they are written to disk only when saved. Since I022 there is also a Wind volume (100 % by default, which is exactly the sound from before). I022: it also keeps the tips setting and the Captain's Academy's progress on this computer (Restore defaults keeps the progress).
- **Works with:** Godot's audio and display, the settings menu, `App` (first-launch language choice), many screens that listen for changes.
- **Keeps:** All the preferences above, in `user://settings.cfg`.
- **When it runs:** Always (an autoload); loaded at start-up.
- **If you change it:** Sound levels, display and accessibility options for every player.

## Navigation and weather

### `src/navigation/anchorage_layer.gd`

**Purpose:** Paints soft coloured water on the chart where the boat could anchor.
- **What it does:** When you switch "Anchorages" on and zoom in close to a coast, it colours the water teal where the normal anchor reaches the bottom and amber where only the Magic Anchor will hold. It works the chart out in 1-degree squares ("tiles"), a little each frame, so the game never stutters.
- **Works with:** `MapView` (which owns it), `CoastalGeography` (where the water is), `DepthService` (how deep it is), `SeaRouter` (water the routes already use), `AnchorSite` (the anchoring rules).
- **Keeps:** The finished tiles as small pictures (at most 48 kept), plus some timing counters for tests.
- **When it runs:** Only on the chart, only while the Anchorages switch is on and you are zoomed in far enough.
- **If you change it:** The highlights could disagree with where the game actually lets you anchor, or the chart could slow down when zooming along a coast.

### `src/navigation/coastal_geography.gd`

**Purpose:** Knows exactly where the water is close to a coast, for anchoring.
- **What it does:** Reads a fine land/water map of the whole world (about half a sea mile per square) and answers: is this spot water, is it clear of the shore, how far is the nearest land, how much open water is upwind, and is there a short safe path from here out to the sea lanes the router uses.
- **Works with:** `SeaRouter` and `NavGrid` (the coarser sailing chart), `DepthService`, `AnchorSite`, `GameSession`, `AnchorageLayer`.
- **Keeps:** The loaded coast file and a cache of up to 512 unpacked map squares.
- **When it runs:** Loaded the first time anything asks about near-shore water (anchoring, the anchorage overlay, waypoints close to land).
- **If you change it:** Which bays you can sail into and anchor in, and whether a waypoint near the shore is allowed.

### `src/navigation/depth_data.gd`

**Purpose:** Reads a real sea-depth file, if one is ever installed.
- **What it does:** Opens a special depth file (made by a tool from real sea-floor data) and looks up the depth at any point. No such file ships with the game today, so it only matters in tests.
- **Works with:** `DepthService` (its only user).
- **Keeps:** The file's bytes and the depth squares it has unpacked so far.
- **When it runs:** Only if a depth file is present; in practice only in tests.
- **If you change it:** Nothing in normal play; tests of real depth data could break.

### `src/navigation/depth_service.gd`

**Purpose:** The one place the game asks "how deep is the water here?".
- **What it does:** Gives a depth for any spot at sea, with a label saying where it came from. Because no real depth data is installed, every depth is a "GAME ESTIMATE": deeper the further from shore, steeper on some coasts, shallower in enclosed bays and shallow seas like the Danish waters. It also turns depths into friendly words like "about 9 m".
- **Works with:** `CoastalGeography`, `DepthData`, `AnchorSite`, `AnchorageLayer`, `GameSession`, the anchor menu.
- **Keeps:** Nothing that changes; the estimate is always the same at the same place in every game.
- **When it runs:** Whenever the game checks an anchorage or shows a depth.
- **If you change it:** Where the normal anchor works and where you need the Magic Anchor, all over the world.

### `src/navigation/geo_math.gd`

**Purpose:** A toolbox of sea-chart maths on longitude and latitude.
- **What it does:** Measures distances in sea miles, works out compass courses, finds points along a route and handles the Date Line (where longitude jumps from 180° east to 180° west). It also writes positions in the usual "55°40.5′N 12°35.0′E" style.
- **Works with:** Almost every navigation piece: `SeaRouter`, `Voyage`, `PlannedRoute`, `MapView`, `WeatherModel`, `Simulation`, `GameSession` and many screens.
- **Keeps:** Nothing of its own; it is only calculations.
- **When it runs:** Constantly, whenever anything needs a distance or position.
- **If you change it:** Distances, travel times, where the boat is drawn and whether routes line up could all go wrong.

### `src/navigation/map_projection.gd`

**Purpose:** Turns longitude and latitude into flat chart coordinates and back.
- **What it does:** Uses the Mercator projection (the classic sea-chart layout where a straight line is a constant compass course) to place things on the drawn chart.
- **Works with:** `MapView`, `CabinWorldMap`, and the tool that prepares the world land.
- **Keeps:** Only its scale (chart units per degree).
- **When it runs:** Whenever a chart is drawn or clicked.
- **If you change it:** Everything on the chart could shift out of place, and the saved world land picture would no longer match.

### `src/navigation/map_view.gd`

**Purpose:** Draws the navigation chart and turns mouse and keyboard into chart actions.
- **What it does:** Draws water, land, coastlines, harbour markers and names, grid lines, weather areas, canals, courses, waypoints, anchorages, the boat and visited-harbour pins. It handles zooming, panning and wrapping round the world, and reports clicks and drags to the chart screen. It also gives the Dreamer's Map its painted colours. Since I021 a special harbour's pin carries a small brass compass star.
- **Works with:** `WorldMap` (which decides what clicks mean), `MapProjection`, `PortCatalog`, `WeatherModel`, `WeatherStyle`, `WindLayer`, `AnchorageLayer`, `SeaRouter` (canals), `NavGrid` (region list), `WorldLand`.
- **Keeps:** What is currently shown (course, waypoints, selected harbour), the camera, and caches of the prepared land so the chart opens quickly next time.
- **When it runs:** While the chart table or the cabin's Dreamer's Map is open.
- **If you change it:** How the chart looks and feels, how fast it opens and pans, and whether clicks land on the right harbour or waypoint.

### `src/navigation/nav_grid.gd`

**Purpose:** The sailing map that says where a boat may go.
- **What it does:** Holds a grid over the world where each square is open water, "approach" water near harbours, or land. It can check whether a straight course crosses land. Finer grids for Europe and Denmark sit inside the world grid, and the world wraps round at the Date Line.
- **Works with:** `SeaRouter` (its main user), `CoastalGeography`, `AnchorageLayer`, `WindLayer`, `MapView`, the chart plotter.
- **Keeps:** The grid squares loaded from the data files and its finer regional grids.
- **When it runs:** Loaded once with the router (on the loading screen), then used for every route check.
- **If you change it:** Routes could cross land, or real sea lanes could be blocked.

### `src/navigation/planned_route.gd`

**Purpose:** A planned course: where it starts, your waypoints, the destination and the exact line to sail.
- **What it does:** Holds the course the router worked out, which waypoints are anchorages, and splits it into legs. It can describe itself ("Copenhagen → Kiel · 152 nm") and turn itself into save data and back, checking that saved data makes sense.
- **Works with:** `SeaRouter` (makes it), `Voyage`, `GameSession`, `SessionState`, `WorldMap`, `PortCatalog`.
- **Keeps:** Start, waypoints, anchorage marks, destination and the path points.
- **When it runs:** Whenever a course is planned, sailed, saved or loaded.
- **If you change it:** Saves (planned courses and voyages) could stop loading, or the boat could sail a different line than the chart shows.

### `src/navigation/port_catalog.gd`

**Purpose:** The list of every harbour in the game.
- **What it does:** Finds harbours by their id, by area (only the ones on screen) or by name in the harbour search.
- **Works with:** `PortData` (each harbour), `MapView`, `WorldMap`, `SeaRouter`, `GameSession`, the save system, and many menus.
- **Keeps:** The harbours from `data/navigation/port_catalog.tres` and quick-lookup indexes.
- **When it runs:** Loaded on the loading screen and shared by the whole game.
- **If you change it:** Harbour search, which harbours appear on the chart, and whether saves recognise their harbours.

### `src/navigation/port_data.gd`

**Purpose:** The facts about one harbour.
- **What it does:** Stores a harbour's id, name (shown in your language), country, position, description and how important it is (which decides from which zoom level it appears on the chart). Since I021 it also gives the harbour's sentence in the current language.
- **Works with:** `PortCatalog` and everything that shows or routes to harbours.
- **Keeps:** Just that harbour's facts.
- **When it runs:** Loaded with the harbour list.
- **If you change it:** Changing a harbour's `id` breaks saves that mention it; changing its position moves it on the chart and changes routes.

### `src/navigation/sea_router.gd`

**Purpose:** Works out sea routes that never cross land, and checks routes.
- **What it does:** Finds a course between harbours and through your waypoints using a prepared network of open-water points, then straightens it. It finds a way out of each harbour, can use the Kiel and Suez canals, and can reach anchorages close to shore. It also checks a whole route before it is used and moves a waypoint dropped on land to the nearest water.
- **Works with:** `NavGrid`, `PortCatalog`, `PlannedRoute`, `CoastalGeography`, `GeoMath`, `GameSession`, `WorldMap`, `VoyageDaydream`, `TrafficModel`.
- **Keeps:** The route network, harbour exit paths and recent route pieces (cached).
- **When it runs:** Loaded on the loading screen; used whenever a course is plotted or changed.
- **If you change it:** Which places can be reached, how long routes are, and whether routes ever cross land.

### `src/navigation/traffic_model.gd`

**Purpose:** Makes up other ships at sea for the radar and VHF radio.
- **What it does:** Places cargo ships, tankers, ferries, fishing boats and yachts near the boat, more near busy harbours. Each ship follows a straight track on water. The same place and time always gives the same ships, even after loading a save. It also works out how close a ship will pass.
- **Works with:** `Simulation`, the radar panel, `VhfRadio`, `SeaRouter`, `PortCatalog`.
- **Keeps:** A cache of ship tracks; nothing is saved.
- **When it runs:** When the game looks for nearby ships (radar, traffic warnings).
- **If you change it:** How busy the sea feels and when you get "ship passing close" warnings.

### `src/navigation/vessel_profile.gd`

**Purpose:** How fast one boat sails, and when it switches to the engine.
- **What it does:** Turns wind speed and wind angle into a sailing speed (with a spinnaker bonus downwind), gives the engine speed, the rules for when to motor, and how well the boat handles heavy weather.
- **Works with:** `GameSession`, `PropulsionController`, `WeatherDamage`, `VesselDefinition`, the boatyard menu.
- **Keeps:** The boat's tuning numbers (stored in boat files such as `data/vessel/starter_sloop.tres`).
- **When it runs:** Whenever the boat is sailing.
- **If you change it:** Boat speeds, passage times and how often the engine runs.

### `src/navigation/voyage.gd`

**Purpose:** The voyage you are sailing right now.
- **What it does:** Holds the course being sailed and how far along it the boat is; the boat's position is always worked out from these. It also keeps the voyage record for the Captain's Log (distance sailed, worst weather, damage), anchorage stops, and standing by for a ship in need.
- **Works with:** `PlannedRoute`, `GameSession`, `SessionState`, the save system, `WorldMap`, `CaptainsLog`.
- **Keeps:** Progress, revision, warnings already given, departure details, log numbers, anchorage progress.
- **When it runs:** While the boat is underway.
- **If you change it:** Where the boat is, saves of voyages at sea, and the Captain's Log figures.

### `src/navigation/voyage_daydream.gd`

**Purpose:** Writes the Captain's daydream about a far-away voyage on the Dreamer's Map.
- **What it does:** When you press "Imagine this voyage", it plans a real route, picks up to three real harbours along it and writes a few friendly lines in one of five moods. It never changes anything in the game.
- **Works with:** `SeaRouter`, `PortCatalog`, `PassageReadiness`, `GameSession`, `WorldMap`.
- **Keeps:** A small cache of recent daydreams.
- **When it runs:** Only when you ask on the Dreamer's Map.
- **If you change it:** Only the daydream text and the route it shows.

### `src/navigation/weather_legend.gd`

**Purpose:** The small key in the chart's Weather tab explaining the weather symbols.
- **What it does:** Draws one row per weather kind (gale, thunderstorm risk, thunderstorm, cyclone) with its colour, outline, symbol and name.
- **Works with:** `WeatherStyle`, `WorldMap` (which adds it).
- **Keeps:** Nothing of its own.
- **When it runs:** While the chart's Weather tab is shown.
- **If you change it:** Only how the legend looks.

### `src/navigation/weather_style.gd`

**Purpose:** Decides how each kind of weather looks on the chart.
- **What it does:** One table of colours, fills, outline styles (solid, dashed, dotted) and labels, plus code that draws the symbols (wind lines, cloud, lightning bolt, spiral). Both the chart and the legend use it, so they always match.
- **Works with:** `MapView`, `WeatherLegend`, `WorldMap`, `WeatherEvent`, `WeatherModel`.
- **Keeps:** Nothing that changes.
- **When it runs:** Whenever weather is drawn on the chart.
- **If you change it:** The look and labels of weather areas.

### `src/navigation/wind_layer.gd`

**Purpose:** The chart's wind arrows and the faint colour wash on the sea.
- **What it does:** Shows where the wind blows, coloured by strength, using exactly the same wind the boat sails in. You can step the picture up to six hours back or forward. It works a little each frame so panning stays smooth, and hides itself when zoomed far out ("Zoom in to see wind details").
- **Works with:** `MapView` (which owns it), `WeatherModel`, `NavGrid`, `GameSession`, `WorldMap` (buttons and legend).
- **Keeps:** Recent wind pictures (up to 14 times) and which grid points are land.
- **When it runs:** Only while the chart is open with the Wind switch on.
- **If you change it:** Only what the chart shows; the real sailing wind does not depend on it.

### `src/navigation/world_land.gd`

**Purpose:** A ready-made package of the world's land shapes for the chart.
- **What it does:** Holds the world's land outlines already converted to chart coordinates, so the chart opens quickly without reading a big text file.
- **Works with:** `MapView`, `CabinWorldMap`, and the tool `tools/navigation/world_land_to_res.gd` that makes it.
- **Keeps:** Land shapes, coastlines, small islands as dots, and place names.
- **When it runs:** Loaded when a chart first opens.
- **If you change it:** The world file must be rebuilt with the tool, or the chart falls back to the slower text file.

### `src/navigation/world_map.gd`

**Purpose:** The chart screen: plan, edit and follow your course.
- **What it does:** Runs the chart table: pick a destination, plot a course, add, drag and remove waypoints, mark anchorages, then Apply or Discard. It shows status, ETA, wind, weather along the course and Passage Readiness, has a harbour search, and switches the wind and anchorage overlays. In the cabin it becomes the Dreamer's Map with "Imagine this voyage". Since I021 a special harbour's details also say why it is special, and the harbour's sentence follows the language.
- **Works with:** `MapView`, `GameSession`, `SeaRouter`, `PortCatalog`, `Simulation`, `VoyageDaydream`, `PassageReadiness`, `AnchorSite`, `WeatherLegend`, `WindLayer`.
- **Keeps:** The draft course being edited (it never changes your real course until you press Apply).
- **When it runs:** When the chart table or the cabin's map is opened.
- **If you change it:** How course planning works, and the chart screen's layout and buttons.

### `src/weather/weather_event.gd`

**Purpose:** One piece of dangerous weather: a gale area, thunderstorm risk area, thunderstorm or tropical cyclone.
- **What it does:** Describes where the event is, how big and how strong at any moment as it grows, moves and fades, with a slightly irregular outline and, for storms, gusty bursts. Asking about it never changes it.
- **Works with:** `WeatherModel` (which creates events), `WeatherStyle`, `MapView`, `Simulation`, weather sound.
- **Keeps:** A few fixed numbers set when the event forms.
- **When it runs:** Whenever weather is sampled or drawn.
- **If you change it:** How storms move and how strong they feel; the same seed would give different weather.

### `src/weather/weather_exposure.gd`

**Purpose:** Remembers what weather the boat is in now and since when.
- **What it does:** Records the current danger level, which event is responsible, and the strongest wind and gusts during it. It resets in harbour.
- **Works with:** `SessionState` (owns it), `GameSession` (updates it, fed by `Simulation`), `SaveManager`, `WeatherModel`, `WeatherSample`.
- **Keeps:** Danger level, start time, weather type, event id, peak wind and gust.
- **When it runs:** Updated every 5 game minutes while underway.
- **If you change it:** Saves (it is stored in them). Little in the game acts on it today, but tests use it to check that the weather is the same at every game speed.

### `src/weather/weather_model.gd`

**Purpose:** The game's weather: the one answer to "what is the weather here, now?".
- **What it does:** Starts from the everyday wind (`WindField`) and adds gales, thunderstorm risk areas and storms, and tropical cyclones, each formed by season and sea area. It gives wind, gusts, danger level and a weather type, and lists the storms existing at a time. The same seed, place and time always give the same weather.
- **Works with:** `WindField`, `WeatherEvent`, `WeatherSample`, `Simulation`, `GameSession`, `MapView`, `WindLayer`, the HUD, weather sound and many others.
- **Keeps:** The weather settings from `data/weather/weather_events.json` and caches of events.
- **When it runs:** Always, whenever anything asks about weather.
- **If you change it:** Every storm, warning, weather damage and sailing speed in the game.

### `src/weather/weather_sample.gd`

**Purpose:** The weather at one place and time, as one package.
- **What it does:** Holds the steady wind, gusts, background wind, danger level, weather type, the responsible storm, thunder flags and cyclone season risk.
- **Works with:** `WeatherModel` (fills it), `Simulation`, `GameSession`, `AnchorSite`, the HUD, `WorldMap`, weather sound.
- **Keeps:** Only the values of that one reading.
- **When it runs:** Each time the weather is asked for.
- **If you change it:** Anything that reads weather details (warnings, HUD text, anchoring).

### `src/weather/wind_field.gd`

**Purpose:** The everyday background wind everywhere in the world.
- **What it does:** Blends typical winds from about 40 places in Europe and from world wind belts (trade winds, westerlies, calms) into a smooth wind, then adds slow changes over days. The same place, time and seed always give the same wind. It also gives compass names like "WSW".
- **Works with:** `WeatherModel` (its main user), `PropulsionController`, the HUD, `Simulation`, `AnchorSite`, the radar and sailing panels.
- **Keeps:** The wind settings from `data/weather/wind_climate.json` and two precomputed wind grids.
- **When it runs:** Always, whenever wind is needed.
- **If you change it:** Wind everywhere, and with it sailing speeds and passage times.

## Boats, decks, cabins and the world around them

### `src/aboard/anchor_ambience.gd`

**Purpose:** Works out the "quiet evening at anchor" mood (a colour tint and a cabin-lamp strength) while the boat lies settled at anchor.
- **What it does:** Every half second it checks the time of day and whether the boat is settled at anchor, then eases a tint and a lamp glow towards the right mood. Since Iteration 17 it no longer shows anything itself (it is hidden); the boat's lighting does the real light, and this node only keeps the numbers for the anchor moments and the tests.
- **Works with:** `GameSession` (time of day, settled at anchor), `AnchorLife` (the tints and lamp strengths), `BoatArea` (which adds it and tells it where the cabin lamps are).
- **Keeps:** The current and target tint and lamp strength, and the list of cabin lamp spots.
- **When it runs:** Whenever you are on deck or in the cabin (one per boat area).
- **If you change it:** Little is visible in play today; mostly the anchor-mood tests would notice.

### `src/aboard/anchor_life.gd`

**Purpose:** The rule book for a calm, safe stay at anchor: what time of day it is aboard and which gentle lines the game shows.
- **What it does:** Turns game time and the boat's longitude into a local hour and a phase (morning, day, evening, night). Holds the tints, lamp strengths and the short quiet lines ("The anchor holds. The sea is quiet.") and picks one in a repeatable way.
- **Works with:** `GameSession` (which decides when the boat is settled and records the moments), `AnchorAmbience`, `AboardBadge`, `CompanionState` (the cat and dog lines).
- **Keeps:** Nothing of its own; only fixed rules and texts.
- **When it runs:** Whenever the game asks about time of day aboard or a moment at anchor.
- **If you change it:** The evening/night timing, the wind limit for feeling "settled" (18 kn), the delay before the first quiet line and the texts the Captain reads at anchor all change.

### `src/aboard/cabin_decor.gd`

**Purpose:** Draws one of the Captain's cosy cabin things (rug, herbs, framed chart, oil lamp, book shelf, flag bunting) and finds a good place for each.
- **What it does:** Each item is drawn in simple hand-drawn shapes, with no collision. A placement helper puts wall things along the hull sides, alternating starboard and port, and the rug on open floor near the middle, always clear of stations and the companion's resting spots. The same cabin always gives the same places. Since I021 it also draws a model ship, a jar of sea glass and a brass barometer, and since Operation Paperwork a brass compass. Things that find no wall on the first try get a second look, from inside each hull and a little closer together, so all ten fit in every cabin; nothing already placed moves.
- **Works with:** `BoatArea` (creates and places them), `HarbourTrades` (the list of decor items and whether each goes on wall or floor), `CabinHomeMenu` (where the Captain chooses them).
- **Keeps:** Which item it is and which wall side it hangs on.
- **When it runs:** In the cabin, when it loads or when the Captain changes the chosen decor.
- **If you change it:** The look and placement of cabin decorations; a placement mistake could put a thing over a station or the cat's bed.

### `src/aboard/coffee_mug.gd`

**Purpose:** Draws the Captain's coffee mug where it stands: in the cup holder by the helm on deck, or on the cabin table.
- **What it does:** On deck it always draws the brass cup holder, and the mug inside it when the coffee is there. It redraws when the coffee moves. It also offers a mug drawing that the sailor figure uses when carrying the coffee.
- **Works with:** `GameSession` (where the coffee is), `BoatArea` (creates the holder and the table mug), `SailorDrawing` (borrows the mug drawing).
- **Keeps:** Only which place it shows ("holder" or "table").
- **When it runs:** Whenever you are on deck or in the cabin.
- **If you change it:** How the mug and holder look, on deck, on the table and in the Captain's hand.

### `src/aboard/galley_stove.gd`

**Purpose:** Draws the little two-burner stove in the galley, with a pan that steams after a meal is cooked.
- **What it does:** Draws the stove and pan; when a meal is cooked it lights the burners and lets steam rise for about 12 seconds. It only shows things: the station beside it opens the cooking menu.
- **Works with:** `GameSession` (the "meal cooked" message), `BoatArea` (places it), `HighlightResolver` (its outline for the focus highlight).
- **Keeps:** How long the steam has left and a small animation clock.
- **When it runs:** In the cabin.
- **If you change it:** Only the look of the stove and its steam.

### `src/aboard/rod_holder.gd`

**Purpose:** Draws the fishing rod in its holder on the stern rail, with the line trailing astern and the tip nodding when a fish bites.
- **What it does:** Draws holder, rod and reel; while the line is out it draws a gently moving line into the water; when a fish is on, the rod tip nods. The station beside it opens the fishing menu.
- **Works with:** `GameSession` (line out, fish bite), `BoatArea` (places it on the port rail near the stern).
- **Keeps:** A small animation clock.
- **When it runs:** On deck.
- **If you change it:** Only how the rod looks and moves; fishing rules are elsewhere.

### `src/aboard/trophy_board.gd`

**Purpose:** The wooden trophy board on the cabin wall, with five slots for the Captain's most notable catches.
- **What it does:** Shows a small picture of each trophy fish (or a coloured fish shape) and faint outlines for empty slots ("still to catch"). It refreshes whenever fishing changes or a game is loaded. The station beside it opens the trophy list.
- **Works with:** `GameSession` (the fishing record), `FishingState` (how many trophies), `FishArt` (fish pictures), `BoatArea` (places it), `HighlightResolver`.
- **Keeps:** The five picture holders on the board.
- **When it runs:** In the cabin.
- **If you change it:** The look of the board; the ranking of trophies is decided elsewhere.

### `src/aboard/windlass.gd`

**Purpose:** Draws the anchor windlass (the winch for the anchor chain) on the foredeck.
- **What it does:** When the anchor is up, it draws the anchor stowed in the bow roller; at anchor it draws the chain running over the bow into the water, and a pulsing red ring if the anchor is dragging. The station beside it opens the anchor menu.
- **Works with:** `GameSession` (anchored or not, anchor state), `AnchorState`, `BoatArea` (places it on the foredeck).
- **Keeps:** Where the bow roller is and a small animation clock.
- **When it runs:** On deck.
- **If you change it:** Only the look of the windlass and chain, including the dragging warning picture.

### `src/boat/anchor_signals.gd`

**Purpose:** Shows everyone the boat is at anchor: the black anchor ball in the rigging, the anchor line into the water and a small marker buoy.
- **What it does:** Visible only while actually anchored. Draws the ball between mast and bow, a rope curving to a bobbing buoy (straighter when dragging), and a special brass look for the Magic Anchor. Drawn pictures from the Sprite Workshop can replace the ball and buoy.
- **Works with:** `GameSession`, `AnchorState`, `BoatArea`, `BoatLighting` (boat outline), `SailRig` (mast spot), `ArtworkResolver` (replacement art), `SettingsManager` (reduce motion).
- **Keeps:** Bow and mast positions, an animation clock and any replacement pictures. Nothing is saved.
- **When it runs:** On deck.
- **If you change it:** What being at anchor looks like on deck.

### `src/boat/boat_area.gd`

**Purpose:** The heart of each deck and cabin scene: it places the Captain, sets up everything aboard and turns "pressing E at something" into requests for the game.
- **What it does:** On load it applies the boat's art, adds lighting, weather, water life, anchor signs, the companion on deck, the fishing rod, windlass, stove, trophy board, coffee spots and cabin decor. It handles the camera (wider underway, turned to the course, following you ashore), the walk onto the pontoon in harbour and the short docking arrival. When you use a station it sends a request (open chart, sleep, cook…) for the app to handle; it never opens menus itself. Petting the companion shows the occasional kind word (`CompanionRemarks`), or a friendly look when your hands are full. I022: the deck's water takes its softer colour from WaterLook with a faint sea bed in shallow water (ShallowWater), and the Starling 33's cabin gets its windows (CabinWindows), shown with the illustrated art only.
- **Works with:** `GameSession`, `Player`, `Interactable`, `VesselVisual`, `SailRig`, `BoatLighting`, `ShoreAccess`, `HarbourDressing`, `WaterLife`, `App` (which listens to its requests).
- **Keeps:** Camera settings, the shore stations and the docking animation; it writes the Captain's position back to the game state.
- **When it runs:** Whenever you are on deck or in the cabin.
- **If you change it:** Almost everything aboard can be affected: where the Captain appears after loading, which stations exist and what they do, the camera and the harbour arrival.

### `src/boat/boat_fixture.gd`

**Purpose:** The invisible "solid shape" of a piece of furniture or fitting, so the Captain cannot walk through it.
- **What it does:** Builds a collision shape from a rectangle or custom outline; can be marked walkable (hatches, floor panels). In the game it draws nothing; in the Godot editor it shows a see-through outline so the layout can be edited.
- **Works with:** `BoatArea`, `BoatLighting` (lamps and shadows follow fixture names), `HighlightResolver` (highlights furniture), `CabinDecor` placement, `DeckCompanionSpots`.
- **Keeps:** Its size, outline and whether it is solid.
- **When it runs:** Whenever a deck or cabin is loaded (and in the editor).
- **If you change it:** Where the Captain can walk on every boat; renaming fixtures can also move lamps and highlights.

### `src/boat/boat_lighting.gd`

**Purpose:** Day and night aboard: the colour of the light, the cabin lamps, the navigation and anchor lights, and soft shadows.
- **What it does:** Follows the game clock and the boat's position to tint the scene (sky light on deck, daylight through hatches below). Lights warm lamps at the boat's own furniture, red/green/white navigation lights at night underway, a white anchor light at anchor, and quay lamps in harbour. Adds soft shadows under furniture, the Captain and the companion; stormy weather darkens things and lightning gives a gentle flash. Steady Hands / Golden Harbours: how overcast the weather is now comes from one shared function, also used by the cabin windows and the harbour moment.
- **Works with:** `BoatArea`, `Daylight`, `GameSession`, `Simulation` (weather at the boat), `SailRig` (mast), `HarbourDressing`, `Interactable` (keeps highlights bright at night), `SettingsManager` (flash strength).
- **Keeps:** The list of lights, the current light colour and darkness, an overcast amount and the flash level.
- **When it runs:** Whenever you are on deck or in the cabin.
- **Good to know:** Its node is always called "Lighting", in every language, because the boat looks it up by that name.
- **If you change it:** The whole mood of the game by day and night; mistakes could make scenes too dark or lights show at the wrong time.

### `src/boat/cabin_windows.gd`

**Purpose:** The world beyond the cabin windows (I022), so far in the Starling 33's cabin.
- **What it does:** Draws window openings in the illustrated cabin's walls. Each opening shows a small slice of the world around the boat: sky in the colours of the hour and the weather, the sun where it really is, stars at night, the sea with crests that grow with the wind, the harbour's own picture on the quay side when moored, and rain on the glass. Which slice depends on the boat's heading, which side the window is on, and where the captain stands: walking past a window turns the view, and up close it shows more. The window frames are drawn over the scenery, and the furniture stays in front. It now asks the boat lighting how overcast it is (one shared rule).
- **Works with:** `BoatArea` (adds it), `WaterLook` (the sea's colour), `HarbourLooks` (the harbour art), `Daylight`, `Simulation` (weather, heading), `data/vessels/cabin_windows.json` (where the windows are).
- **Keeps:** The windows, the world as last sampled, where the captain stood.
- **When it runs:** It redraws only when the captain moves or every two seconds (about 0.35 ms per redraw).
- **If you change it:** Windows for another boat need measured openings that lie inside that cabin's wall art; the test checks every corner. Keep it free of shaders and per-frame work.

### `src/boat/cabin_world_map.gd`

**Purpose:** The framed world map on the cabin wall, with pins for harbours visited and the boat.
- **What it does:** Draws a small wooden-framed chart of the whole world from the game's land data, with pins for the harbours in the Captain's Log and the boat's position. Using it opens the Dreamer's Map. It also lends its world shapes to the voyage map.
- **Works with:** `GameSession` (visited harbours, boat position), `PortCatalog`, `MapView`/`WorldLand` (land data), `HighlightResolver`, `VoyageMap`.
- **Keeps:** The world's land shapes, worked out once per game run and shared.
- **When it runs:** In the cabin.
- **If you change it:** The wall map's look and the voyage map, which reuses its land drawing.

### `src/boat/fender_stowage.gd`

**Purpose:** Hides the fenders (the white bumpers on the boat's side) while sailing and shows them in harbour.
- **What it does:** Finds the white fender shapes painted in the deck picture, makes a copy of the picture with them removed, and swaps between the two. The original art files are never changed.
- **Works with:** `BoatArea` (asks it when sailing starts or ends), `VesselVisual`/`VisualSlot` (the deck pictures).
- **Keeps:** A memory of the fenders found per picture, for the rest of the run.
- **When it runs:** On deck, when the art is applied and when the boat leaves or reaches harbour.
- **If you change it:** Whether fenders show correctly; a mistake could erase other white parts of the deck art.

### `src/boat/provision_display.gd`

**Purpose:** Shows the food and water on board as real things in the cabin: bread, apples, a jar, cheese and four water jugs.
- **What it does:** Each item stands for 3.5 days; full items are filled, used ones are faint outlines, low stores turn amber and empty ones red. If the boat's art folder has drawn pictures for the stores, those are shown instead. The station next to it opens the provisions menu.
- **Works with:** `GameSession` (food and water days), `Provisions` (levels and capacity), `VesselVisualProfile` (optional pictures), `Loc` (the label).
- **Keeps:** The food and water days it last showed.
- **When it runs:** In the cabin (it also shows in the Godot editor).
- **If you change it:** How the Captain sees at a glance whether stores are running low.

### `src/boat/sail_rig.gd`

**Purpose:** Draws the sails seen from above: mainsail, jib and, on downwind courses, the spinnaker.
- **What it does:** Reads the sail state from the game and trims the sails smoothly to the wind, on the side away from the wind. Sails "breathe" a little, purely for looks. Sails are furled in harbour and at anchor. It can use drawn sail pictures and the sail cloth colour chosen at the sailmaker, and turns see-through when the Captain walks under it.
- **Works with:** `GameSession` (propulsion state, underway, anchored), `VesselVisualProfile` (sail pictures), `HarbourTrades` (sail cloth colours), `BoatArea`.
- **Keeps:** Attachment points from the boat's layout, the current sail angles and how far each sail is set.
- **When it runs:** On deck.
- **If you change it:** The look of sailing; it never changes how fast the boat goes.

### `src/boat/visuals/damage_overlay.gd`

**Purpose:** Draws wear and damage on top of the boat's art as its condition gets worse.
- **What it does:** Nothing when the boat is sound; scuffs and rust when worn; cracks and damaged planking when damaged; many cracks and water on the cabin floor when critical. The marks are placed the same way every time for each boat; drawn damage pictures can replace them.
- **Works with:** `VesselVisual` (creates it), `VesselCondition` (the condition bands), `VesselVisualProfile` (optional damage pictures), `ProceduralShape`.
- **Keeps:** The current condition and band, and the list of mark positions.
- **When it runs:** On deck and in the cabin, whenever the boat's condition is shown.
- **If you change it:** How a worn or damaged boat looks.

### `src/boat/visuals/procedural_shape.gd`

**Purpose:** A simple stand-in drawing: a filled shape with an outline and an optional label.
- **What it does:** Draws a rectangle or custom outline, and a label in its middle. It is only a picture; the matching solid shape is a `BoatFixture`.
- **Works with:** `VisualSlot` (holds these as its placeholder art), `DamageOverlay` (uses their outlines).
- **Keeps:** Its size, outline, colours and label text.
- **When it runs:** Whenever placeholder art is shown (and in the Godot editor).
- **If you change it:** The look of every boat part that has no drawn picture.

### `src/boat/visuals/solar_panels.gd`

**Purpose:** Decorative solar panels on each boat's stern, purely for looks.
- **What it does:** Draws dark-blue panels with a cell grid, frame, shadow and struts (and an arch for two or more panels), or a drawn picture from the Sprite Workshop. They give no power and are not saved, and they sit outside the walkable deck.
- **Works with:** `VesselVisual` (creates it from the boat's panel list), `ArtworkResolver` (replacement picture).
- **Keeps:** The panel rectangles.
- **When it runs:** On deck.
- **If you change it:** Only the look of the panels.

### `src/boat/visuals/vessel_visual.gd`

**Purpose:** The root of a boat's deck or cabin artwork, deciding for each layer whether to show a drawn picture or the placeholder drawing.
- **What it does:** Applies the boat's art profile layer by layer, allowing Sprite Workshop replacements, adds the solar panels and the wear-and-damage overlay. It has no collision, so changing art never changes gameplay.
- **Works with:** `VisualSlot`, `VesselVisualProfile`, `ArtworkResolver`, `SolarPanels`, `DamageOverlay`, `BoatArea`, `BoatyardMenu` (boat preview), `FenderStowage`.
- **Keeps:** The art canvas size, the solar panel list and the current profile.
- **When it runs:** On deck and in the cabin, and in the boatyard preview.
- **If you change it:** How every boat's art is chosen and layered.

### `src/boat/visuals/vessel_visual_profile.gd`

**Purpose:** A settings file that says which artwork each part of a boat uses.
- **What it does:** For every art layer it looks first at a picture set in the editor, then at a correctly named picture file in the boat's art folder, and otherwise keeps the placeholder drawing, so a missing file never makes the boat disappear. It does the same for damage pictures.
- **Works with:** `VesselVisual`, `VesselDefinition`, `SailRig`, `DamageOverlay`, `ProvisionDisplay`, `BoatArea`.
- **Keeps:** The art folder, the "placeholder only" switch and the assigned pictures (stored in `data/vessels/*_visuals*.tres`).
- **When it runs:** Whenever boat art is shown.
- **If you change it:** Which pictures every boat shows; renaming layer files breaks the "drop a picture in the folder" workflow.

### `src/boat/visuals/visual_slot.gd`

**Purpose:** One named layer of a boat's artwork (hull, deck, cabin roof…), showing either a drawn picture or the placeholder shapes.
- **What it does:** When given a picture, it hides the placeholder shapes and stretches the picture over the whole art canvas (warning if the picture's shape does not match); otherwise it shows the placeholder.
- **Works with:** `VesselVisual`, `VesselVisualProfile`, `FenderStowage`.
- **Keeps:** Its layer name and the picture it shows.
- **When it runs:** Whenever boat art is shown.
- **If you change it:** How drawn pictures line up on every boat.

### `src/boat/shallow_water.gd`

**Purpose:** A hint of the sea bed through shallow water (I022).
- **What it does:** Draws a few large, very faint sandy patches in the water around a moored or anchored boat, over the water colour and under the crests and the hull. Each harbour always gets the same patches. It is hidden at sea and when the water's translucency is 0.
- **Works with:** `BoatArea` (adds it next to the water), `WaterLook`, `GameSession` (leaving, arriving, anchoring).
- **Keeps:** The pattern's seed.
- **When it runs:** It draws once, and again only when the boat leaves or returns to shallow water.
- **If you change it:** Keep it faint.

### `src/boat/water_look.gd`

**Purpose:** Softer, more translucent-looking water (I022).
- **What it does:** Gives the colour of the water around the boat: the old deep blue-green with a little of a sandy sea-bed colour showing through, a little more in harbour or at anchor where the water is shallow. It is a plain colour blend, with no shader and no transparency. Day and night light, crests and ripples still lie over it. Its strength is one setting, separate from the window glass tint, and 0 gives exactly the old water.
- **Works with:** `BoatArea` (the deck's water), `ShallowWater`, `CabinWindows`.
- **Keeps:** Only the strength setting.
- **When it runs:** When a deck scene opens and when the boat leaves, arrives or anchors.
- **If you change it:** Keep the water clearly water; the test checks it stays dark enough and that 0 is the old colour.

### `src/boat/weather_visuals.gd`

**Purpose:** Shows the weather on deck: light wind streaks drifting with the wind, and rain when it rains.
- **What it does:** Twice a second it reads the wind and rain at the boat. Streaks move where the wind blows, faster and more of them in stronger wind; rain falls slanted by the wind, following the same rule as the rain sound.
- **Works with:** `BoatArea`, `GameSession`, `Simulation` (weather and heading), `WeatherAudio` (rain level).
- **Keeps:** The current wind direction and strength, the rain amount and the streaks and drops on screen (at most 40 and 260).
- **When it runs:** On deck.
- **If you change it:** How wind and rain feel on deck; only the look.

### `src/interaction/highlight_provider.gd`

**Purpose:** A small invisible helper that tells the highlight system the outline of a drawn object (like the stove or windlass).
- **What it does:** Holds an outline and offers it so the station's glow traces the real object when the Captain stands near it. It draws nothing itself.
- **Works with:** `HighlightResolver`, `BoatArea` (adds one to each piece of aboard gear), `HarbourDressing`.
- **Keeps:** The outline points.
- **When it runs:** Aboard and on the pontoon, whenever highlights are worked out.
- **If you change it:** Which objects glow when focused.

### `src/interaction/highlight_resolver.gd`

**Purpose:** Decides what should glow when the Captain can use something: the real object, not an invisible circle.
- **What it does:** First looks for an object that says it belongs to that action, then the nearest matching piece of furniture (chart table, berth, galley…), and otherwise a small soft outline of the station area. Also gives handy rounded-rectangle and circle outlines.
- **Works with:** `Interactable`, `BoatFixture`, `HighlightProvider`, `BoatArea`, `CabinWorldMap`, and aboard gear like `GalleyStove`.
- **Keeps:** Nothing of its own; only fixed lists of furniture names.
- **When it runs:** When a deck or cabin is set up and when stations change.
- **If you change it:** Which object glows for each action; how close you must be to use things is not affected.

### `src/interaction/interactable.gd`

**Purpose:** Anything the Captain can use by standing close and pressing E (a "station").
- **What it does:** Its shape sets how close you must be. When used, it sends a message; the scene that owns it decides what happens, or it just shows a short text. While focused it glows softly around its object, and it stays bright at night.
- **Works with:** `InteractionSensor` (picks which one is focused), `BoatArea` (routes the action), `HighlightResolver`, `BoatLighting`.
- **Keeps:** Its action id, prompt text, on/off switch, priority and highlight outline.
- **When it runs:** Whenever you are aboard or ashore near it.
- **If you change it:** Every usable thing in the game; very wide impact.

### `src/interaction/interaction_sensor.gd`

**Purpose:** The Captain's "reach": it finds usable things nearby and keeps exactly one in focus.
- **What it does:** Picks the nearest station, but lets stations win over the companion unless you face the animal. Pressing E always uses the same thing the prompt shows; ties are broken predictably by name.
- **Works with:** `Interactable`, `Player` (sits inside the player and asks which way it faces).
- **Keeps:** Which station is focused now.
- **When it runs:** Every physics step while you are aboard.
- **If you change it:** Which station E uses when several are close, including petting the cat or dog.

### `src/player/player.gd`

**Purpose:** The Captain aboard: walks with the keys, bumps into furniture and uses things with E.
- **What it does:** Moves at a set speed (the keys follow the screen even when the deck view is turned), remembers which way it faces, swings its arms while walking and draws itself as a little sailor, carrying the hat or the coffee when it has them. It ignores input while menus are open.
- **Works with:** `InteractionSensor`, `SailorDrawing`, `PlayerHat`, `GameSession` (coffee), `BoatArea`.
- **Keeps:** Facing direction, walk animation, whether input is on, and the view's rotation.
- **When it runs:** Whenever you are on deck or in the cabin.
- **If you change it:** How the Captain moves and feels to control; collision size changes where you can walk.

### `src/player/sailor_drawing.gd`

**Purpose:** Draws the Captain from above as a little sailor in a striped jumper.
- **What it does:** Draws shadow, swinging arms with hands, the striped body, hair and a hint of face, and the coffee mug in hand when carrying it. The same inputs always give the same drawing.
- **Works with:** `Player` (uses it to draw), `CoffeeMug` (the mug drawing), `PlayerHat` (draws the hat on top).
- **Keeps:** Nothing of its own; only colours and sizes.
- **When it runs:** Whenever the Captain is drawn.
- **If you change it:** The Captain's look; the hat's position depends on the head's centre staying where it is.

### `src/vessels/vessel_catalog.gd`

**Purpose:** The list of all boats the Captain can own, in boatyard order.
- **What it does:** Loads the boat list once, finds a boat by id and names the starter boat (the Arctic Wanderer 26), which is also the safe fallback for unknown ids.
- **Works with:** `VesselDefinition`, `GameSession`, `SaveManager`, `SessionState`, `BoatyardMenu`, `CaptainsLogMenu`, `App`.
- **Keeps:** The list of boats (from `data/vessels/vessel_catalog.tres`).
- **When it runs:** Whenever the game needs boat information, from loading onwards.
- **If you change it:** Which boats exist and which one a new game starts with; changing the starter id affects old saves.

### `src/vessels/vessel_definition.gd`

**Purpose:** Describes one boat: its id, name, description, sailing performance, deck and cabin scenes and art.
- **What it does:** Pure data, one file per boat. It picks the illustrated art when the Artwork setting asks for it, gives the right scene for deck or cabin, and checks that the boat is complete. Since I022 each boat has a price in euros.
- **Works with:** `VesselCatalog`, `GameSession`, `VesselVisualProfile`, `BoatArea`, `BoatyardMenu`, `Provisions` (passage stores), `SettingsManager`.
- **Keeps:** The boat's facts (stored in `data/vessels/*.tres`).
- **When it runs:** Whenever the game asks about the active boat.
- **If you change it:** Every boat's set-up; saves store only the id, so a boat's id must never change.

### `src/water/water_life.gd`

**Purpose:** Makes the water around the boat come alive with small hand-drawn movements.
- **What it does:** In harbour: ripple rings, wavelets, glints, water lapping at the hull and pontoon, and a few floating things that fit the harbour (marina, coastal or city). At sea: wave crests set by the wind (white crests from 20 kn) streaming past with the boat's speed, and floating seaweed, driftwood and feathers. Only shown with the illustrated art style.
- **Works with:** `BoatArea`, `GameSession`, `Simulation` (wind at the boat), `HarbourArt`, `PortCatalog`, `SettingsManager`.
- **Keeps:** A fixed number of waves, drifters and rings, reused all the time, and the wind it last read.
- **When it runs:** On deck, every frame while visible.
- **If you change it:** The feel of the sea and harbours, and possibly the frame rate.

### `src/world/day_night_watch.gd`

**Purpose:** Handles dawn and dusk gently: when twilight starts in normal play, it shows a date card and lets the twilight pass behind it.
- **What it does:** Watches the sun at the boat; when it notices dawn or dusk beginning, it asks the app to show the card while time passes normally (stores, weather, events) until full day or night. Sleeping, loading and other time jumps never count, and long polar twilights get no card.
- **Works with:** `App` (shows the card), `Daylight`, `GameSession`, `Simulation`, `TimePassage`.
- **Keeps:** The last time and sun height it looked at.
- **When it runs:** Always during play (paused when menus pause the game).
- **If you change it:** How often play is interrupted by dawn and dusk cards.

### `src/world/daylight.gd`

**Purpose:** Works out where the sun is for the boat, from the game clock and position.
- **What it does:** A simple sun formula: local sun time from longitude, the season from the date, and the sun's height. From that it gives night, dawn, day or dusk, how much daylight there is, and the colour of the light outside and in the cabin (greyer in stormy weather).
- **Works with:** `BoatLighting`, `DayNightWatch`, `UiTheme`, `MusicDirector`.
- **Keeps:** Nothing of its own; only fixed colours and rules.
- **When it runs:** Whenever lighting, the interface or music checks the time of day.
- **If you change it:** When it gets dark and light everywhere in the game, and the colours of every scene.

## Life aboard and ashore: companion, fishing, galley, hat, harbour trades, sailing, care, audio, developer tools

### `src/anchor/anchor_site.gd`

**Purpose:** The rulebook for where the boat can anchor and how well the anchor holds.
- **What it does:** For a spot on the map it answers three separate questions: can the boat get there safely, is the water the right depth for the normal anchor (or only the Magic Anchor), and how sheltered is it from today's wind. It also works out whether an anchor is holding well, fairly, poorly or dragging, and writes the friendly descriptions shown on the chart.
- **Works with:** `CoastalGeography` (land, shore distance, open water upwind), `DepthService` (estimated depth), `WindField`/`WeatherSample` (the wind), `AnchorState` (holding levels), `Loc` (translations).
- **Keeps:** Nothing of its own; just fixed rules (depth limits, wind limits, holding numbers).
- **When it runs:** Whenever the game checks an anchorage: on the chart, in the anchor menu, and while the boat lies at anchor.
- **If you change it:** Which places count as good, fair or poor anchorages, when the anchor drags in strong wind, and the texts players read about anchoring.

### `src/anchor/magic_anchor_deployment.gd`

**Purpose:** The little timing game you play when letting the Magic Anchor go.
- **What it does:** Sets up a round dial (shared with the fishing reel) that needs 1–3 good stops depending on the wind, with a slightly narrower target in harder wind. Three misses end the attempt; perfect stops make the anchor bite a little more firmly.
- **Works with:** `TimingCheck` (the dial itself), the anchor menu, and `GameSession.drop_magic_anchor`, which does the real anchoring.
- **Keeps:** The current dial and how many attempts have been made.
- **When it runs:** Only while the captain is dropping the Magic Anchor.
- **If you change it:** How hard or easy the Magic Anchor is to set, and how well it holds afterwards.

### `src/art/artwork_resolver.gd`

**Purpose:** Lets an artist swap the game's drawn art for their own PNG pictures (the "Sprite Workshop").
- **What it does:** Reads the `manifest.csv` lists in `art_replacements/`, and when a matching PNG exists with the right shape and size, uses it instead of the built-in art. A missing picture is silently skipped; a wrong one is reported as a warning, and the original art stays.
- **Works with:** Drawing code such as `HatArt`, `FishArt`, `CompanionVisualSet` and the boat visuals, which ask it for a picture by name.
- **Keeps:** The list of manifest entries, a memory (cache) of loaded pictures, and the warnings it has given.
- **When it runs:** The first time a piece of art is asked for; after that, from memory. New PNGs show up after restarting the game.
- **If you change it:** Whether hand-drawn replacement art appears in the game, and which pictures are accepted or rejected.

### `src/audio/audio_manager.gd`

**Purpose:** The game's sound player: it plays the music, background sounds and sound effects it is handed.
- **What it does:** Keeps one player for music, one for background "ambience", eight reusable players for short sounds, and named looping sounds (like wind or the engine) that fade in and out without restarting. It never decides what to play; other parts of the game ask it.
- **Works with:** Scenes and menus such as `App`, `WeatherAudio`, the fishing, anchor and cooking menus, and `ShipCompanion`; `MusicDirector` uses its Music channel name.
- **Keeps:** Its sound players, the looping sounds currently playing, and their target volumes.
- **When it runs:** Always (an autoload: a script Godot starts automatically, which is always there), even while the game is paused.
- **If you change it:** Every sound in the game could be affected: volume, fades, sounds cutting each other off.

### `src/audio/music_director.gd`

**Purpose:** Picks which of the three music pieces should be playing and blends between them gently.
- **What it does:** Plays "Lanterns Across the Water" at night, "The Wind Knows the Way" when sailing on deck by day, and "Home Upon the Waves" otherwise (harbour, cabin, at anchor, title screen). It waits a few seconds before changing, crossfades slowly, resumes a piece at the start of a musical phrase, and does not switch day/night music while passage time runs fast.
- **Works with:** `GameSession` (where the boat is, the time, sailing or anchored), `Daylight` (the sun's height), `Simulation` (fast passage time), `AudioManager` (the Music channel).
- **Keeps:** One player per piece, which piece is current, the phrase start times, and its waiting timers.
- **When it runs:** Always (an autoload), checking twice a second.
- **If you change it:** When and how the music changes; too eager settings make the music jump back and forth.

### `src/audio/weather_audio.gd`

**Purpose:** Makes the weather heard aboard: wind, water along the hull, rain, storms and thunder.
- **What it does:** Once a second it sets the volume of looping wind, water, rain and storm sounds from the weather at the boat. Near a thunderstorm it flashes the boat's lights and plays thunder after a delay that grows with distance. Below deck it muffles everything outside. Since I022 the wind (breeze and storm) plays on its own Wind bus, so it has its own volume in Settings; it is still muffled below deck.
- **Works with:** `AudioManager` (plays the loops), `GameSession` (boat speed and position), `WeatherSample`/`WeatherEvent` (the weather), `BoatLighting` (flashes), `SettingsManager` (reduce flashing). Created and fed by `App`.
- **Keeps:** Where the captain is (deck or inside), the current sound levels, and timers for the next lightning and thunder.
- **When it runs:** While a game is going; `App` hands it the weather every real second.
- **If you change it:** How stormy or calm the game sounds, the lightning flashes, and the rain rule that `GameSession` also uses to decide whether the cat or dog may be on deck.

### `src/boat_care/boat_care.gd`

**Purpose:** All the rules for how the boat wears out and what the boatyard charges to fix it.
- **What it does:** Tracks four care areas (hull and bottom, rigging and sails, engine, equipment), turns wear into a level (good, cosmetic, service recommended, needs attention), and works out the small speed loss a worn boat suffers (a few percent at most). It also prices repairs, services and haul-outs (scaled to boat length), reads the list of equipment upgrades, and writes the care texts for menus and the Captain's Log.
- **Works with:** `BoatCareState` (the boat's saved care data), `VesselCondition` (hull condition), `GameSession` (money format), `PortCatalog` (harbour names), the boatyard, chandlery, sailmaker and boat care menus, and `PassageReadiness`.
- **Keeps:** Nothing of its own except a once-loaded copy of the upgrade list from `data/boat/equipment.json`.
- **When it runs:** Whenever wear is added while sailing, speed is worked out, or a care menu or boatyard opens.
- **If you change it:** How fast weed grows on the bottom (fouling) and the rigging wears, how much it slows the boat, and boatyard prices and times.

### `src/boat_care/passage_readiness.gd`

**Purpose:** A friendly checklist before a passage: is the boat ready to go?
- **What it does:** Looks at the hull and care areas, food and water against the expected passage time, the weather forecast along the route (24 hours ahead at most), the passage length and the boat's size. Each finding is OK, worth noting, or worth a second thought. It only advises; it never stops you leaving.
- **Works with:** `GameSession` (boat, condition, provisions), `Simulation` (route time and weather hazards), `BoatCare`, `VesselCondition`, `Provisions`, `GeoMath`; shown by `App`, `WorldMap` and `VoyageDaydream`.
- **Keeps:** Nothing; it works out a fresh answer each time.
- **When it runs:** When a course is planned or a passage is about to start.
- **If you change it:** What advice the captain sees before setting out (for example warnings about stores or rough weather).

### `src/companion/companion_pose_art.gd`

**Purpose:** Describes one pose picture of the cat or dog (resting, sleeping, alert, stretching).
- **What it does:** Holds the pose name, the PNG file to show, and small adjustments: shift, size and mirror. It is a building block of a `CompanionVisualSet`.
- **Works with:** `CompanionVisualSet` (which lists the poses) and, through it, `ShipCompanion`.
- **Keeps:** Just those settings, edited in the Godot inspector or the `.tres` file.
- **When it runs:** When the companion's pictures are loaded.
- **If you change it:** Which picture shows for a pose and how it is placed; a missing file simply makes that pose fall back.

### `src/companion/companion_remarks.gd`

**Purpose:** The kind words the Captain says when petting the ship's cat or dog.
- **What it does:** Holds a few short remarks for a cat and for a dog ("What a lovely little purr."), picks the next one so the same line never comes twice in a row, and translates it into the current language. It is ready for a companion with a name and a gender: then it uses lines with the name ("Who's a good girl, Freja?"), with the name put in exactly as written. Also gives the "your hands are full" line.
- **Works with:** `CompanionState` (who the companion is), `Loc` (English or Danish), `ShipCompanion` (which asks for a remark when petted) and `BoatArea` (which shows it).
- **Keeps:** Nothing; the lines are fixed in the script.
- **When it runs:** When you pet the companion (at most one remark every 15 seconds) or try to with your hands full.
- **If you change it:** What the Captain says when petting; new lines need a Danish translation in `locale/da.po`.

### `src/companion/companion_state.gd`

**Purpose:** The saved facts about the ship's companion: cat or dog, where it is resting, and whether it is in the cabin or on deck.
- **What it does:** Every 2–5 game hours the companion moves to another resting spot in the cabin (settee, chart table, bunk for the cat; floor, companionway, seating for the dog). The choice is worked out from the game clock, not luck, so it is the same at any speed and after loading. It can also be on deck at one of three places.
- **Works with:** `SessionState` (owns it and saves it), `GameSession` (the only one that changes it), `ShipCompanion` (shows it), `SaveManager` (gives old saves a cat).
- **Keeps:** Kind, resting spot, time of the next move, number of moves, area (cabin/deck) and deck place.
- **When it runs:** All the time in a game, as the clock moves forward.
- **If you change it:** Where the cat or dog turns up, and saved games (wrong names or numbers make a save fail to load).

### `src/companion/companion_visual_set.gd`

**Purpose:** The picture set for one companion kind: its poses, size, placement and idle timing.
- **What it does:** Loads each pose picture, shrinks it to save memory, and cuts away a plain paper background if the drawing has none. It works out where to draw the picture on the resting spot. It also holds how long the animal rests, naps, stretches and looks up. A Sprite Workshop replacement picture is used when one exists.
- **Works with:** `CompanionPoseArt` (each pose), `ArtworkResolver` (replacement art), `ShipCompanion` (draws it); sets live in `data/companions/cat_visuals.tres` and `dog_visuals.tres`.
- **Keeps:** Its settings, plus a shared memory (cache) of prepared pictures.
- **When it runs:** When a companion appears in the cabin, on deck, or in the New Game preview.
- **If you change it:** How the cat and dog look and behave when idle; without a usable resting picture the game draws a simple built-in animal instead.

### `src/companion/deck_companion_spots.gd`

**Purpose:** Finds safe places on deck where the cat or dog can lie, and safe walking routes between them.
- **What it does:** From each boat's own layout it picks three resting places (aft, middle, forward) and the way up at the companionway. Places stay inside the lifelines, clear of fittings like the mast and benches, and away from the wheel and other stations. Walks follow lines that never go over the side.
- **Works with:** `BoatArea` (which builds it), `BoatFixture` and `Interactable` (fittings and stations), `ShipCompanion` (which walks the paths).
- **Keeps:** The deck outline, fittings, the marker spots it made, and a grid used for finding paths.
- **When it runs:** Once when the deck is built; then whenever the companion walks.
- **If you change it:** Where the companion lies on deck, and whether it could appear over the water or in the captain's way.

### `src/companion/ship_companion.gd`

**Purpose:** The cat or dog you see and can pet, in the cabin or on deck.
- **What it does:** Shows the companion at its resting spot, with pose pictures (resting, napping, stretching, looking up) or a simple drawn animal if no pictures exist. Pressing E pets it: a purr and hearts for the cat, panting and a wagging tail for the dog, and now and then (at most every 15 seconds) a kind word from the Captain, chosen by `CompanionRemarks`. When it changes between cabin and deck while you watch, it walks there. At a quiet anchorage it curls up for long naps.
- **Works with:** `GameSession` and `CompanionState` (where it should be), `CompanionVisualSet` (pictures), `DeckCompanionSpots` (deck places and paths), `AudioManager` (sounds), `Interactable` and `HighlightResolver` (petting and glow), `SessionLog`. Placed in each cabin scene and built on deck by `BoatArea`; also used as a preview in the New Game menu.
- **Keeps:** Only how it looks right now (pose, walk, reaction); nothing is saved.
- **When it runs:** Whenever the cabin or deck is on screen.
- **If you change it:** How the companion looks, moves and reacts to petting.

### `src/dev/dev_guides.gd`

**Purpose:** Finds the developer guides (the Markdown files in `DEV_GUIDES/`) so they can be read inside the game.
- **What it does:** Lists the guide files with the `README.md` index first, reads a guide's text, and takes each guide's title from its first heading. The guides are only offered in development (debug) builds where the files are present.
- **Works with:** `DevGuidesMenu` (the in-game viewer), `MainMenu` (shows the button) and `App`.
- **Keeps:** Only which folder to read from (tests can point it elsewhere).
- **When it runs:** When the main menu decides whether to show the guides button, and when the guide viewer opens.
- **If you change it:** Which guides appear in the in-game viewer and in what order; players of the finished game never see this.

### `src/dev/dev_test_panel.gd`

**Purpose:** The developer's test panel (F10): buttons to test weather, damage, rescue, food and time on purpose.
- **What it does:** Shows buttons for test storms and gales, setting the boat's condition, a rescue test, setting food and water, and jumping time forward, plus a live status line about the boat and weather. The game pauses while it is open.
- **Works with:** `DevTools` (does the actual work), `GameSession`, `Simulation`, `Provisions`, `VesselCondition`; opened by `App` (F10) or the pause menu.
- **Keeps:** Only its own buttons and status label.
- **When it runs:** Only when a developer opens it, in builds run from the Godot editor.
- **If you change it:** Only the developer test tools; nothing in the normal game.

### `src/dev/dev_tools.gd`

**Purpose:** Developer-only shortcuts that make rare situations happen right away so they can be checked.
- **What it does:** Creates test weather (a gale, a storm, a thunder squall, or a storm on the course ahead), sets the boat's condition or stores, prepares a rescue test, and moves time forward through the normal simulation. Test weather is never saved and is removed whenever a game starts, loads or ends.
- **Works with:** `WeatherFixtures` (makes the test weather), `GameSession`, `Simulation`, `GeoMath`; used by `DevTestPanel`, `App` and the pause menu.
- **Keeps:** Which test weather is active, and a switch tests use to turn the tools on or off.
- **When it runs:** Only in debug builds run from the Godot editor (and not with `--no-dev-tools`).
- **If you change it:** Developer testing only, but a mistake could leak test weather into a real game.

### `src/dev/weather_fixtures.gd`

**Purpose:** Makes hand-placed weather (gales, thunderstorms, cyclones) for tests and developer tools.
- **What it does:** Builds weather events at a chosen place, time and strength that behave exactly like the game's natural weather, and puts them into the weather model, optionally switching off the normal random weather. `clear()` puts everything back to normal.
- **Works with:** `WeatherModel` and `WeatherEvent` (the weather system), `Simulation` (clears its estimates), `DevTools`, and many test suites.
- **Keeps:** Nothing of its own; it changes the weather model's test list.
- **When it runs:** Only in automated tests and developer tools, never in normal play.
- **If you change it:** Many automated tests could start failing, because they rely on this exact weather.

### `src/fishing/fish_art.gd`

**Purpose:** Finds the painted pictures of each fish, shark and piece of junk.
- **What it does:** Reads `data/fishing/fish_art.json` to learn each picture's size, tail pivot and whether it moves, and loads the picture layers (body, tail, closed eye, or one picture for junk) plus a small thumbnail. A Sprite Workshop replacement wins if there is one.
- **Works with:** `FishPortrait`, the fishing menu, the trophy menu and trophy board, and `ArtworkResolver`.
- **Keeps:** A once-loaded copy of the picture information.
- **When it runs:** Whenever a catch is shown: reeling in, the result, the cool box, the trophy board.
- **If you change it:** How catches look everywhere in the game.

### `src/fishing/fish_portrait.gd`

**Purpose:** Shows a caught fish large and alive: it blinks, flicks its tail and bobs gently.
- **What it does:** Stacks the fish's picture layers and animates them with irregular timing so two fish never blink together. Junk just lies still. With "reduce motion" on, only the blink stays.
- **Works with:** `FishArt` (the pictures), `SettingsManager` (reduce motion); used by the fishing menu.
- **Keeps:** Which fish it shows and its animation timers.
- **When it runs:** While a fish is shown large in the fishing screens; it stops working when hidden.
- **If you change it:** The look and liveliness of caught fish.

### `src/fishing/fishing_catalog.gd`

**Purpose:** The fishing rulebook: lures, fish species, junk, where fish bite, and what they are worth.
- **What it does:** Reads `data/fishing/fishing.json` and decides which fish can bite where (by the nearest harbour's region, and coastal fish only near land), the chance of a bite (lower in strong wind, none when trolling too fast), the fish and its weight, size grades (bronze, silver, gold), how hard reeling in is by rarity, trophy score and sale price. Choices use a dice roll the game seeds, so the same moment always gives the same bite.
- **Works with:** `PortCatalog` and `GeoMath` (regions), `HatStory` (distance to open water), `FishingState`, `GameSession`, `Simulation`, and the fishing, fishmonger, grocery, chandlery and trophy menus.
- **Keeps:** The loaded fishing data (one shared copy).
- **When it runs:** Whenever someone fishes, sells fish, or looks at catches.
- **If you change it:** Which fish players catch where, how often, how big, how hard, and how much they earn.

### `src/fishing/fishing_sounds.gd`

**Purpose:** A small list of short sound cues for fishing, the galley and the anchor.
- **What it does:** Hands out the cast, bite, reel, splash, line-snap, frying sizzle, anchor chain and warning beep sounds, all played quietly. Each sound also has something you can see, so nobody needs to hear it.
- **Works with:** `AudioManager` (plays them), `App` and the fishing, cooking and anchor menus.
- **Keeps:** Nothing; it just loads the sound files.
- **When it runs:** When those actions happen.
- **If you change it:** Which sounds play for fishing, cooking and anchoring.

### `src/fishing/reel_timing.gd`

**Purpose:** The reel-in game for a catch: press while the needle is inside the target arc.
- **What it does:** It is the shared timing dial (`TimingCheck`) used for fishing. Rarer fish need more good presses and have a narrower target; a perfect press makes the landed fish a little heavier. Three misses lose the fish, and doing nothing for a minute lets it slip away. The file only adds the fishing name and description; the dial itself lives in `TimingCheck`.
- **Works with:** `TimingCheck`, `FishingCatalog` (how many presses and how wide), the fishing menu and `ReelDial` (draws it).
- **Keeps:** Same as the dial: needle position, target, hits, perfects and misses.
- **When it runs:** While reeling in a bite.
- **If you change it:** Changes to the dial itself happen in `TimingCheck`, and also affect the Magic Anchor.

### `src/galley/recipes.gd`

**Purpose:** The galley's simple dishes and what each one gives.
- **What it does:** Lists five dishes (porridge, bread and soup, pan-fried fish, fish stew, a sailor's supper) with how many fish and how much food they use, cooking time, and how long the crew stays "well fed". Fish dishes turn fish into extra days of food, at most three days per dish.
- **Works with:** `GameSession` (does the cooking) and the cooking menu.
- **Keeps:** Nothing but the fixed recipe list.
- **When it runs:** When the captain cooks in the galley.
- **If you change it:** How useful fishing and cooking are for the food stores.

### `src/harbour/harbour_art.gd`

**Purpose:** Optional extra art for one particular harbour: up to three landmark pictures and the water's mood.
- **What it does:** Looks for a file `data/harbours/<port_id>.tres` (only Copenhagen has one so far). If found, it gives the landmark pictures to draw beyond the guest pontoon (at most three) and says whether the water should feel like a marina, a coast or a city. Harbours without a file just get the normal illustrated harbour.
- **Works with:** `HarbourLandmark` (each picture), `HarbourDressing` (draws them), `WaterLife` (uses the water mood).
- **Keeps:** The harbour id, its landmarks and the water mood setting.
- **When it runs:** When the boat lies in a harbour and the harbour scenery is drawn.
- **If you change it:** How a special harbour looks; landmarks are pictures only and never block walking or mooring.

### `src/harbour/harbour_dressing.gd`

**Purpose:** Draws the illustrated harbour around the moored boat: pontoon, ropes, cleats, stone quay, water ripples, service signs and landmarks.
- **What it does:** Reads where the existing pontoon, mooring lines and stations are, and paints a hand-drawn harbour over them with wooden signs for the grocery store, boatyard and Go Ashore. With the Artwork setting on "Classic" it hides itself and the old simple drawing shows. It also tells the lighting where the quay lamps and pontoon lights are. Since I021 the view beyond the quay comes from HarbourLooks: the harbour's own landmark, or the illustration of its look.
- **Works with:** `BoatArea` (which adds it), `HarbourArt` and `HarbourLandmark`, `SettingsManager` (art style), `GameSession` (which harbour), `HighlightProvider`/`HighlightResolver` (sign glow), `Interactable` stations.
- **Keeps:** Shapes it read from the deck, the current signs and landmarks, and the classic sign texts so it can switch back.
- **When it runs:** Whenever the boat is moored in a harbour and the deck is shown; refreshed when the harbour or setting changes.
- **If you change it:** The look of every harbour; it is art only and does not change walking, mooring or buttons.

### `src/harbour/harbour_facilities.gd`

**Purpose:** Says which services a harbour has: grocery store, boatyard, haul-out yard, Go Ashore, and the trades that follow from them.
- **What it does:** Uses a file in `data/harbours/facilities/` if one exists for that harbour; otherwise every harbour gets everything, and major harbours can also haul boats out. It sorts harbours into small, larger or major service harbours and writes the service summary shown on the chart.
- **Works with:** `PortCatalog` (which harbours are major), `HarbourTrades` (chandlery, sailmaker, fishmonger), `BoatArea` (shore stations), `GameSession`, `WorldMap`, and the shop menus.
- **Keeps:** Four on/off switches per harbour, plus a memory (cache) of loaded harbour files.
- **When it runs:** When arriving in a harbour, opening a shop, or looking at a destination on the chart.
- **If you change it:** Where the player can buy food, repair, haul out or visit the trades.

### `src/harbour/harbour_landmark.gd`

**Purpose:** One landmark picture for a harbour (for example Nyhavn in Copenhagen).
- **What it does:** Holds a title, the picture, where it sits relative to the quay, and how wide to draw it.
- **Works with:** `HarbourArt` (lists it) and `HarbourDressing` (draws it).
- **Keeps:** Just those four settings.
- **When it runs:** When the harbour scenery is drawn.
- **If you change it:** The size and place of a landmark picture; it never affects gameplay.

### `src/harbour/harbour_looks.gd`

**Purpose:** Decides what each harbour looks like beyond the guest pontoon, and which harbours are special (I021).
- **What it does:** Reads the harbour look table (`data/harbours/harbour_looks.json`). Every harbour has a look chosen for what the place really looks like: Nordic timber, a gabled harbour town, Atlantic stone, Mediterranean, an Aegean island, a stone town, a tropical town, a tropical island or a volcanic island. A harbour with its own picture (like Copenhagen's Nyhavn or Valletta's bastions) shows that instead, and those few are the special harbours marked with a star on the chart. It also gives the picture for the arrival card.
- **Works with:** `HarbourArt` and `HarbourLandmark` (the pictures), `HarbourDressing` (draws them), `MapView` and `WorldMap` (the star and the "Special harbour" line), `App` (the arrival card), `Loc` (names in Danish).
- **Keeps:** The table it read, and each look's picture once it has been used (so visiting many harbours of the same look costs nothing extra).
- **When it runs:** Whenever you moor, arrive, or look at a harbour on the chart.
- **If you change it:** What harbours look like and which are marked special; a missing picture just shows the plain quay, never an error.

### `src/harbour/harbour_trades.gd`

**Purpose:** The harbour trades: the chandlery, the sailmaker and the fishmonger, and the little things you can buy for the cabin.
- **What it does:** Reads the catalogue `data/harbours/trades/trades.json`. A harbour with a grocery store has a fishmonger; one with a boatyard has a chandlery and a sailmaker. It gives the cabin decorations, sailcloth colours and prices, the chandlery's upgrades, the Magic Anchor's price, and a fishmonger's name that is the same on every visit.
- **Works with:** `HarbourFacilities`, `GameSession`, `HomeState`, `CabinDecor`, `SailRig` (sail colours), `BoatArea`, and the chandlery, sailmaker, fishmonger, boat care and cabin home menus.
- **Keeps:** A once-loaded copy of the trades catalogue.
- **When it runs:** When the trades' menus open, the cabin is decorated, or the sails are drawn.
- **If you change it:** What the trades sell and for how much, and how sails look; everything here is optional for sailing.

### `src/harbour/shore_access.gd`

**Purpose:** Lets the captain walk ashore: a gangplank from the boat down to the pontoon and a strip of pontoon to walk on.
- **What it does:** From each boat's own layout it places the gangplank, opens a gap in the rail exactly there, and builds walls so the boat, plank and pontoon become one walkable area. It offers places along the pontoon for the service stations. Underway, the rail closes again and the plank disappears.
- **Works with:** `BoatArea` (owns it and places the stations), `GameSession` and `SessionLog` (notes when the player crosses).
- **Keeps:** The pontoon and shore strip shapes, the gangplank position, the extra walls, and whether the player is ashore.
- **When it runs:** On decks with a mooring; switched on in harbour and off at sea.
- **If you change it:** Whether the player can get on and off the boat, or gets stuck at the rail.

### `src/harbour/shore_events.gd`

**Purpose:** The small library of cozy "Go Ashore" moments in a harbour.
- **What it does:** Holds short scenes like a harbour café, a friendly sailor or gulls eyeing your sandwich, each with one or two choices that cost a few euros and some time. Some harbours (Copenhagen, Lohals) and regions (Atlantic islands, Caribbean, Central America, Pacific) add their own. The first time you make a choice in a harbour it can give a little renown and goes into the Captain's Log.
- **Works with:** `GameSession` (runs the choice and the reward), `PortCatalog` (the harbour's region), the Go Ashore menu.
- **Keeps:** Nothing but the fixed texts; which moments you have had is saved elsewhere.
- **When it runs:** When the captain chooses Go Ashore in a harbour.
- **If you change it:** The texts, costs and renown of harbour outings; renaming an event can make it count as new again.

### `src/hat/hat_art.gd`

**Purpose:** The pictures of the captain's hat: hanging on its hook, worn on the head, and tumbling away in the wind.
- **What it does:** For each of the three looks it uses, in order: a picture set in the settings file, then a PNG named `hat_<look>.png` in the art folder, then the simple drawn hat. A Sprite Workshop replacement wins when there is one. It also draws the chosen picture at the right size and turned the right way.
- **Works with:** `HatDrawing` (the drawn fallback), `ArtworkResolver`, `HatHook`, `PlayerHat`, `HatBlowAway`, the hat badge; settings in `data/hat/hat_art.tres`.
- **Keeps:** Which pictures to use, their sizes, and a switch to force the drawn hat.
- **When it runs:** Whenever the hat is drawn.
- **If you change it:** How the hat looks; it never changes whether you have the hat.

### `src/hat/hat_blow_away.gd`

**Purpose:** The short "your hat is gone!" animation on deck.
- **What it does:** The hat tumbles downwind, lifts a little, leaves wind streaks and fading echoes, and disappears after about 2.8 seconds. It is just for show; the actual loss is handled by `GameSession`.
- **Works with:** `HatArt` (the tumbling picture); created by `BoatArea` when the hat blows away.
- **Keeps:** Its direction and how far along the animation is.
- **When it runs:** Only for those few seconds after the hat is lost on deck.
- **If you change it:** How noticeable and fun the moment of losing the hat is.

### `src/hat/hat_config.gd`

**Purpose:** The balancing numbers for the captain's hat: its price and how wind strains a worn hat.
- **What it does:** Reads `data/hat/hat_config.json`. It works out how much strain a worn hat gathers each game minute in a given wind and gusts (half as much in a sheltered harbour), and how much strain each hat can take before it blows away (fixed per hat, between two limits).
- **Works with:** `Simulation` (checks the hat every game minute), `GameSession` and `HatState` (apply the result).
- **Keeps:** The price, the wind bands, gust bands, recovery speed, warning timing and the strain limits.
- **When it runs:** Whenever the game checks the hat in the wind.
- **If you change it:** How often hats blow away and what a new one costs at the grocery store.

### `src/hat/hat_drawing.gd`

**Purpose:** The simple built-in drawing of the captain's hat, seen from above.
- **What it does:** Draws a white crown, a navy band, a shiny black peak and a small brass badge with a slightly wobbly ink outline, so it fits the hand-drawn look. Used whenever there is no picture for the hat.
- **Works with:** `HatArt` (calls it as the fallback).
- **Keeps:** Nothing; only colours.
- **When it runs:** Whenever the hat is drawn without a picture.
- **If you change it:** The look of the default hat everywhere.

### `src/hat/hat_hook.gd`

**Purpose:** The brass hook in the cabin where the captain's hat hangs.
- **What it does:** Draws the hook, and the hat on it while the hat is stored. It glows when the cabin's hat station is selected.
- **Works with:** `GameSession` (the hat's state), `HatArt`, `HighlightResolver`; placed at each cabin's `Layout/HatSpot` by `BoatArea`.
- **Keeps:** Only whether the hat is hanging there right now.
- **When it runs:** While the cabin is on screen.
- **If you change it:** How the hook and the hanging hat look in the cabin.

### `src/hat/hat_story.gd`

**Purpose:** The words around the captain's hat: messages and Captain's Log lines when a hat blows away.
- **What it does:** Names where it happened from the game's real state ("in Copenhagen harbour", "about 12 nm off Skagen"), picks a light-hearted loss message, and writes the log line with the actual wind and gusts. It also measures how far open water reaches around a point, which fishing uses too.
- **Works with:** `PortCatalog`, `GeoMath`, `SeaRouter`/`NavGrid` (the sea chart), `WeatherSample`/`WeatherModel`; used by `GameSession` and `FishingCatalog`.
- **Keeps:** Nothing but its fixed messages.
- **When it runs:** When a hat is lost, and whenever fishing asks if a spot is near the coast.
- **If you change it:** The hat texts players read, and which fish count as coastal.

### `src/hat/player_hat.gd`

**Purpose:** The hat on the captain's figure: on the head, or tucked under the arm.
- **What it does:** Follows the hat's state from the game and draws it on the head turned the way the captain faces, or carried in the hand. It is only a picture; the captain moves and collides the same with or without it.
- **Works with:** `GameSession` (hat state), `HatArt`, `HatState`; added to the captain by `Player`.
- **Keeps:** What it shows right now and which way the captain faces.
- **When it runs:** Whenever the captain is on screen.
- **If you change it:** How the hat looks on the captain.

### `src/sailing/propulsion_controller.gd`

**Purpose:** Decides automatically whether the boat sails or uses the engine.
- **What it does:** Works out how fast the boat could sail in this wind and heading, averages it over about an hour of game time, and switches to the engine when sailing is too slow (or the boat is becalmed) and back to sails when the wind is good again. Minimum times stop it flipping back and forth. A change of course can make it decide right away.
- **Works with:** `PropulsionState` (its memory), `VesselProfile` (the boat's numbers), `WindField` (the wind), `SailTrim` (trim speeds up or slows the sails only); called by `Simulation`.
- **Keeps:** Nothing itself; it returns an updated copy of `PropulsionState`.
- **When it runs:** At every simulation step while underway.
- **If you change it:** When the engine starts and stops, and the boat's speed under sail.

### `src/sailing/propulsion_state.gd`

**Purpose:** The saved record of what drives the boat right now: sails or engine, speed, and the controller's memory.
- **What it does:** Holds the mode (sail or engine), why the engine is on, the averaged sailing potential, timers, the wind and heading at the last check, and whether the spinnaker is set. It writes the HUD line like "Under sail · broad reach · 6.8 kn" and checks saved data when loading.
- **Works with:** `PropulsionController` (updates it), `SessionState` (saves it), `Simulation`, `GameSession`, `SaveManager`, the HUD, sailing panels, `SailRig` and `WorldMap`.
- **Keeps:** Mode, engine reason, speeds, timers, heading, wind and spinnaker.
- **When it runs:** All the time while sailing; saved with the game.
- **If you change it:** Saved games (fields must stay readable) and what the HUD says about sailing.

### `src/sailing/sail_trim.gd`

**Purpose:** The small sail-trim skill: leave it to the crew, or set the sheets yourself.
- **What it does:** Works out the best sheet setting for the wind angle (tight when close-hauled, eased when running, a bit flatter in strong wind). A good setting makes the boat up to 6 % faster, a poor one up to 10 % slower. It never changes whether the engine runs. It also gives feedback words like "Well trimmed" or "Too loose".
- **Works with:** `Simulation` and `PropulsionController` (apply the speed), `GameSession`/`SessionState` (store the setting), the sail trim and sailing panels.
- **Keeps:** Nothing; only rules.
- **When it runs:** At each sailing step and when the captain moves the trim slider.
- **If you change it:** How rewarding hand-trimming the sails is.

### `src/sailing/weather_damage.gd`

**Purpose:** Works out how much heavy weather wears the boat down.
- **What it does:** Ordinary breezes and strong winds do nothing; above about 28 kn of wind or 45 kn of gusts the boat loses condition, a little in a gale and a lot in a storm. It checks the weather once each game minute, so the result is the same at any game speed or while sleeping. Each boat's toughness factor scales the damage.
- **Works with:** `WeatherModel` (the weather), `Simulation` (calls it), `GameSession` (owns the boat's condition), `VesselProfile` (toughness factor).
- **Keeps:** Nothing; only the rules.
- **When it runs:** At every simulation step while underway.
- **If you change it:** How dangerous storms are, how often repairs and rescues happen.

### `src/skills/timing_check.gd`

**Purpose:** The shared timing dial: a needle goes round, and you press while it is inside the target arc.
- **What it does:** The needle always moves at the same speed. Each good press counts; after enough, you succeed. A smaller "Perfect" zone sits inside the arc. Misses are allowed up to a limit (three by default), not pressing costs nothing, and a minute without pressing ends it. Nothing happens by luck except where the target appears, which is fixed by a seed.
- **Works with:** `ReelTiming` (fishing), `MagicAnchorDeployment` (the Magic Anchor), `ReelDial` (draws it), the fishing and anchor menus.
- **Keeps:** Needle position, target, number of hits, perfects and misses, and the result.
- **When it runs:** While reeling in a fish or setting the Magic Anchor.
- **If you change it:** The feel of both fishing and Magic Anchor mini-games.

## User interface: menus, panels and the HUD

### `src/ui/aboard_badge.gd`

**Purpose:** The small silent status lines on the screen (the HUD) under the hat badge, so you never have to rely on hearing a sound.
- **What it does:** Shows up to four lines: "Fish on! Reel in R" (pulsing), the anchor's holding (or a red "Anchor dragging!"), "Line out · trolling" (amber when too fast to troll), and "Well fed" after a warm meal.
- **Works with:** `Hud` (which creates it), `GameSession`, `AnchorSite`, `AnchorLife`, `FishingCatalog`, `UiTheme`.
- **Keeps:** Nothing of its own; it re-reads the game every frame and saves nothing.
- **When it runs:** Always while the HUD is on screen, every frame.
- **If you change it:** The on-screen warnings for bites, anchor dragging and trolling speed change, which matters for players who play without sound.

### `src/ui/academy_guide.gd`

**Purpose:** The Captain's Academy in play (I022): one small card in the lower right corner for the First Voyage and the tips.
- **What it does:** During the First Voyage it shows the current step and ticks it off when the player really does it (walks, opens the wheel and the log, goes on deck, opens the chart, plans a course, sets sail, lets time run), always with Skip. Afterwards it shows short tips the first time something happens (the first time underway, a harbour, a weather warning, a bite, traffic, the cabin ...), each once, with Read more and Got it. The card steps aside whenever a window, a warning, a time passage or the voyage map is up, and at the chart it stays clear of the chart's buttons.
- **Works with:** `App` (its windows, screens and Handbook), `Academy`, `GameSession` and `Simulation` signals, `SettingsManager` (tips on or off), `HUD` (warnings).
- **Keeps:** The tips waiting, the tip shown, whether the player has walked.
- **When it runs:** A few times a second while the game runs; it does nothing else.
- **If you change it:** Keep the rule: never over a window or a warning, and always closable.

### `src/ui/action_wheel.gd`

**Purpose:** The ring of actions that opens with Q.
- **What it does:** Places the actions that make sense where you are (helm, cabin, at anchor, in harbour) in a ring; arrow keys or A/D move round it, E/Enter chooses, Q or Esc closes. On/off items show a check box.
- **Works with:** `App` (which gives it the list from `App.get_wheel_actions()`), `ModalPanel` / the modal stack, `UiTheme`.
- **Keeps:** Only the list of actions it was given and which one is selected.
- **When it runs:** When you press Q (or open it) during play.
- **If you change it:** How players reach many everyday actions; it never adds new actions itself, it only offers existing ones.

### `src/ui/anchor_menu.gd`

**Purpose:** The anchor panel at the windlass (the anchor winch on the foredeck).
- **What it does:** Before anchoring it judges the anchorage here in this wind and lets you choose how much chain to let out (3, 5 or 7 times the depth), then a small timing game sets the anchor. At anchor it shows the holding, lets you change chain, set it again, acknowledge the alarm or raise the anchor. It also runs the Magic Anchor's timing dial.
- **Works with:** `GameSession`, `AnchorState`, `AnchorSite`, `DepthService`, `MagicAnchorDeployment`, `ReelDial`, `App` (spends the time each job takes), `AudioManager`, `SessionLog`.
- **Keeps:** Only the state of the setting game and of a Magic Anchor attempt while the panel is open; the anchor itself lives in `GameSession`.
- **When it runs:** When you use the windlass (or choose the anchor on the action wheel).
- **If you change it:** Anchoring feel and how long anchoring takes in game time; how well the anchor holds depends on how well you time the "Set it now" press.

### `src/ui/anchorage_prompt.gd`

**Purpose:** The question "We've arrived at our anchorage. Ready to drop anchor?" when the boat reaches an anchorage waypoint on its course.
- **What it does:** Offers three choices: drop anchor (opens the normal anchor panel), not yet (the boat waits), or sail on along the course. It never anchors by itself.
- **Works with:** `App` (shows it and handles the choices), `GameSession`, `AnchorMenu` (indirectly, via the App).
- **Keeps:** Nothing of its own.
- **When it runs:** Once, when the boat arrives at an anchorage waypoint; not again after loading a game.
- **If you change it:** How arriving at a planned anchorage feels and what the captain is offered there.

### `src/ui/boat_care_menu.gd`

**Purpose:** The "Boat care" panel at the boatyard: repairs, services, haul-out and equipment.
- **What it does:** Shows the boat's condition, then only the work this yard can do, each with price and time (or why it is not possible). Lists equipment the yard can fit; gear sold over the counter belongs to the chandlery instead. Steady Hands: the fitted upgrade's name is shown in the chosen language.
- **Works with:** `BoatCareView`, `GameSession`, `BoatCare`, `HarbourFacilities`, `HarbourTrades`, `App` (spends the time ashore and opens the haul-out panel).
- **Keeps:** Nothing of its own; every change goes through `GameSession`.
- **When it runs:** When you choose "Boat care…" in the boatyard while moored in harbour.
- **If you change it:** Prices, waiting times and what work is offered at yards; money and boat condition in saves are changed only by `GameSession`.

### `src/ui/boat_care_view.gd`

**Purpose:** The boat's condition at a glance: one row per care area (hull and bottom, rigging and sails, engine, equipment).
- **What it does:** Shows each area's level in words and colour, a short description and, when it matters, what to do about it.
- **Works with:** `BoatCareMenu` and `CaptainsLogMenu` (both show it), `GameSession`, `BoatCare`, `UiTheme`.
- **Keeps:** Nothing of its own; it only reads the game.
- **When it runs:** When the Boat care panel or the Captain's Log "Boat" tab is open.
- **If you change it:** How the boat's wear is shown in two places at once.

### `src/ui/boatyard_menu.gd`

**Purpose:** The boatyard window, where you browse the boats and move aboard another one.
- **What it does:** Lists every boat with a picture of its deck, its specs and a speed comparison table, and lets you switch boats (free; time, harbour, companion and progress are kept). It also has buttons to Boat care, the grocery store, the chandlery and the sailmaker. Since I022 it shows each boat's price or that it is yours, and offers to buy a boat you do not own yet. Steady Hands: the boats, details and comparison scroll when the screen is too short (at a 130 % interface size it was taller than the screen).
- **Works with:** `App`, `VesselCatalog`, `VesselDefinition`, `VesselVisual`, `GameSession`, `BoatCare`, `Provisions`, `HarbourFacilities`; its layout comes from `boatyard_menu.tscn`.
- **Keeps:** Only which boat is selected in the list.
- **When it runs:** When you use the boatyard while moored in harbour.
- **If you change it:** How boats are chosen and compared, and the way to the yard's other services.

### `src/ui/cabin_home_menu.gd`

**Purpose:** "Make it home": choose which of your cabin things are shown aboard this boat.
- **What it does:** Lists the cabin decorations; owned ones can be shown or put away and appear at once in the cabin beside the panel (nothing is dimmed). Ones not yet bought say they are at the chandlery. Steady Hands: the panel's column on the right is as wide as the panel really is, so it is never partly off screen.
- **Works with:** `TradePanel` (its shared shop look), `HarbourTrades`, `GameSession`, `App` (opens it from the action wheel in the cabin), `CabinDecor` (indirectly, places the things).
- **Keeps:** Nothing of its own; each boat's choice is stored by `GameSession`.
- **When it runs:** In the cabin, from the action wheel.
- **If you change it:** How the cabin decorations are shown; the choices are part of the saved game.

### `src/ui/captains_log_menu.gd`

**Purpose:** The Captain's Log (press L): your statistics, renown, passages, harbours, objectives and the boat's condition.
- **What it does:** Four tabs: Log (stats, renown, a "Publish travel update" button, recent passages and notable moments), Harbours (grouped by country, with filters), Objectives (open, completed and secret achievements, which stay hidden until found) and Boat (condition and boatyard history).
- **Works with:** `GameSession`, `CaptainsLog`, `PortCatalog`, `ObjectiveCatalog`, `VesselCatalog`, `BoatCareView`, `BoatCare`, `Simulation`, `App` (opens it and the publish dialog).
- **Keeps:** Only the harbour filter and which countries are open, for as long as the game runs (not saved).
- **When it runs:** When you press L, or open it from the pause menu or action wheel.
- **If you change it:** What the player sees of their progress; it never changes the game itself.

### `src/ui/catch_badge.gd`

**Purpose:** A small badge showing a fish's rarity and size grade.
- **What it does:** Shows rarity as 1–4 filled diamonds with its name ("Rare") and the grade as a coloured medal with its name ("Silver"), so colour is never the only clue. Junk shows neither.
- **Works with:** `FishingCatalog`, and is used by `FishingMenu` and `TrophyMenu`.
- **Keeps:** Only the rarity and grade it is currently showing.
- **When it runs:** Whenever the fishing panel or trophy board shows a fish.
- **If you change it:** The look of rarity and medals in fishing and on the trophy board.

### `src/ui/chandlery_menu.gd`

**Purpose:** The chandlery (skibshandel): the shop for boat gear, the Magic Anchor, fishing lures and cabin things.
- **What it does:** Lists gear for the boat (fitted once per boat), the Magic Anchor (once, for every boat), lures, and cabin decorations, each with a price button. A purchase is all or nothing and never more than you can afford.
- **Works with:** `TradePanel`, `GameSession`, `HarbourTrades`, `BoatCare`, `FishingCatalog`, `App` (spends fitting time).
- **Keeps:** Nothing of its own.
- **When it runs:** When you open the chandlery from the boatyard, in harbours that have one.
- **If you change it:** What can be bought and for how much; purchases end up in the saved game via `GameSession`.

### `src/ui/chart_plotter.gd`

**Purpose:** The small chartplotter on deck while sailing: your boat, the nearby coast, your course, the next turn and the wind.
- **What it does:** Draws a north-up map around the boat with four ranges (5–80 nm), building the coastline bit by bit from the same water/land grid the route planner uses. It shows text for the next turn or destination and the wind.
- **Works with:** `Hud` (creates it), `App` (toggles it with P or the action wheel), `GameSession`, `Simulation`, `SeaRouter` / `NavGrid`, `WorldMap`, `WindLayer`, `GeoMath`. `TrafficModel` also borrows two of its little map-maths helpers.
- **Keeps:** Whether it is shown and which range is chosen (for this game run only, not saved), and a small picture of the coast.
- **When it runs:** On deck while underway, if switched on.
- **If you change it:** The on-deck navigation aid and possibly frame rate; changing its map-maths helpers also affects other boats' traffic.

### `src/ui/confirm_dialog.gd`

**Purpose:** The general yes/no question box ("Overwrite?", "Load this game?").
- **What it does:** Shows a title, a message and two buttons, answers exactly once and closes. Esc counts as "no", and the cancel button gets the focus first.
- **Works with:** `ModalStack` (which opens it through `confirm()`), and is used by `App`, `SettingsMenu` and `SaveLoadMenu`; its layout comes from `confirm_dialog.tscn`.
- **Keeps:** Only its texts and whether it has answered.
- **When it runs:** Whenever the game asks you to confirm something.
- **If you change it:** Every confirmation in the game, including loading and overwriting saves.

### `src/ui/cooking_menu.gd`

**Purpose:** The galley (kabys): choose a dish and cook it, or make coffee.
- **What it does:** Shows what each recipe needs (fish from the cool box, groceries) and what it gives (food for the stores, being well fed), plays a short pan or coffee-pot animation, then cooks. The stove works in harbour and at a holding anchor, and underway only in moderate weather. Steady Hands: the recipe text and name are shown in the chosen language.
- **Works with:** `GameSession` (`cook()`, `make_coffee()`), `Recipes`, `Provisions`, `App` (spends the cooking time), `AudioManager`, `SessionLog`.
- **Keeps:** Only the animation timers and the last result while the panel is open.
- **When it runs:** When you use the galley stove.
- **If you change it:** Cooking, food stores and the "well fed" bonus; nothing changes when a dish is refused.

### `src/ui/dev_guides_menu.gd`

**Purpose:** A reader for the developer guides (the files in `DEV_GUIDES/`); not part of gameplay.
- **What it does:** Lists the guides by title and shows the chosen one as formatted text, keeping your place when the colour mood changes.
- **Works with:** `DevGuides`, `MarkdownLite`, `UiTheme`, `App` (opens it from the main menu); layout from `dev_guides_menu.tscn`.
- **Keeps:** Which guide is open.
- **When it runs:** Only in development builds, from the main menu.
- **If you change it:** Only how developers read the guides; the game is not affected.

### `src/ui/difficulty_menu.gd`

**Purpose:** The Difficulty dialog of the pause menu (I022).
- **What it does:** Shows the three levels with what each changes and a note that a change counts from now on; Apply sets the new level and says so, Cancel leaves it.
- **Works with:** `DifficultyPicker`, `GameSession.set_difficulty`, `PauseMenu` (opens it), `App`.
- **Keeps:** Nothing of its own.
- **When it runs:** When "Difficulty…" is chosen in the pause menu.
- **If you change it:** Only how the level is changed during a game.

### `src/ui/difficulty_picker.gd`

**Purpose:** Three buttons (Relaxed, Standard, Seasoned Captain) and a line that says what the chosen level changes (I022).
- **What it does:** Shows the choice in the current language, keeps the chosen level and announces changes.
- **Works with:** `Difficulty`, `NewGameMenu`, `DifficultyMenu`.
- **Keeps:** The chosen level.
- **When it runs:** In the New Game menu and the Difficulty dialog.
- **If you change it:** Both places change.

### `src/ui/fishing_menu.gd`

**Purpose:** The fishing rod panel, with three faces: the rod, the reel-in, and the catch.
- **What it does:** At the rod you pick a lure, let the line out or in, wait for a bite, choose which fish to keep and see the cool box (release or sell). When a fish bites, a timing dial reel-in starts; afterwards it shows the catch, its weight, grade and whether it was kept. Steady Hands: lure names are shown in the chosen language.
- **Works with:** `GameSession`, `FishingCatalog`, `FishingState`, `ReelTiming`, `ReelDial`, `FishPortrait`, `FishArt`, `CatchBadge`, `App` (spends waiting time), `AudioManager`, `SessionLog`.
- **Keeps:** Only the current reel-in and the last result while the panel is open; the catch lives in `GameSession`.
- **When it runs:** When you use the rod on the stern rail (or press R when a fish is on).
- **If you change it:** Fishing difficulty and feel, keep rules and the cool box; the catch is saved via `GameSession`.

### `src/ui/fishmonger_menu.gd`

**Purpose:** The fishmonger (fiskehandler): the place where your catch is sold.
- **What it does:** Lists every fish in the cool box with its price, sold one at a time or all at once. Trophies and records stay in the Captain's Log.
- **Works with:** `TradePanel`, `GameSession`, `HarbourTrades`, `FishingCatalog`, `App`.
- **Keeps:** Nothing of its own.
- **When it runs:** From the grocery store's "To the fishmonger…" button, in harbours that have a fishmonger.
- **If you change it:** How much money fishing earns and how selling feels.

### `src/ui/fit_scroll.gd`

**Purpose:** A scroll area that keeps a tall window on the screen (Steady Hands).
- **What it does:** Is exactly as tall as its content when the screen has room, and only as tall as the screen allows when it has not, so the content scrolls while the window's title and buttons stay in view. Used by Settings and the Boatyard, which had grown taller than a 1080-line screen (Settings' title and Apply / Back were cut off).
- **Works with:** `SettingsMenu`, `BoatyardMenu`, `SettingsManager` (the interface size).
- **Keeps:** The window panel it belongs to.
- **When it runs:** When the window size, the interface size or its content changes; never every frame.
- **If you change it:** Keep the title and buttons outside it; only the middle of a window should scroll.

### `src/ui/game_dev_menu.gd`

**Purpose:** A Game Developer at Sea: the captain's little game, opened from the cabin's Q wheel (I022).
- **What it does:** Shows the game's progress towards the next milestone and the devlog of milestones reached, lets the player pick a task (each shows its 2 to 4 hours), answer its one small question, and start working; the hours are shown before starting. An interrupted session waits here with the rest of its time.
- **Works with:** `App` (spends the time and reports the result), `GameSession`, `Pastimes`.
- **Keeps:** The answer chosen.
- **When it runs:** While the dialog is open.
- **If you change it:** Keep it small; the answers change order so the wise one is not always first.

### `src/ui/go_ashore_menu.gd`

**Purpose:** "Go Ashore": a small harbour moment with a little drawn picture and one or two choices.
- **What it does:** Shows the harbour's event (or a "pleasant stroll" if you were just here), each choice with cost and time, then tells what happened. Choices you cannot afford are greyed out. Steady Hands: the choices and "free" are shown in the chosen language.
- **Works with:** `GameSession`, `ShoreEvents`, `App` (settles the choice and spends the time ashore).
- **Keeps:** Only the event being shown.
- **When it runs:** When you go ashore in a harbour that offers it.
- **If you change it:** Shore events, their cost and the renown and notable moments they can add.

### `src/ui/grocery_menu.gd`

**Purpose:** The harbour grocery store: food and water, a long-passage stock-up, a replacement captain's hat and fishing lures.
- **What it does:** Fills food and water up to 14 days each in one purchase, or stocks up beyond that for a long passage (up to what the boat can stow). Also sells a new captain's hat and lures, and has a button to the fishmonger next door. Steady Hands: lure names are shown in the chosen language.
- **Works with:** `GameSession`, `Provisions`, `FishingCatalog`, `HarbourFacilities`, `App` (opens it and the fishmonger).
- **Keeps:** Nothing of its own. It updates itself when your money or your catch changes (for example after selling fish at the fishmonger on top of it).
- **When it runs:** In harbour, from the pontoon's grocery station, the provisions panel or the boatyard.
- **If you change it:** Provision prices and how far you can sail before running out; purchases are saved via `GameSession`.

### `src/ui/handbook_menu.gd`

**Purpose:** The Captain's Handbook window (I022).
- **What it does:** Lists every page by chapter with a search box, shows the chosen page with the real keys filled in, and offers to begin the First Voyage again or to show the tips again. Opens with F1 or from the pause menu, or at a page from a tip's Read more.
- **Works with:** `Academy`, `App` (opens it), `AcademyGuide` (Read more).
- **Keeps:** The page shown and the pages listed.
- **When it runs:** While it is open.
- **If you change it:** Keep the Close button; Esc and F1 close it too.

### `src/ui/harbour_moment.gd`

**Purpose:** The Golden Harbour Moment: a small illustrated travel memory on the first arrival in a harbour that has a picture.
- **What it does:** Shows a card in the notice column with the harbour's own picture set in a sky and a sea for the hour. By day the picture is as drawn; at dawn there is a pale sky and a little mist; at dusk the sky is warm, the picture's own windows begin to glow and lanterns line the quay; at night the picture is dimmed and its windows are lit. Under the picture come the harbour's name, its description, the Captain's Log line and a "First visit" stamp ("Special harbour" for the harbours with their own art). A click puts it away, and it fades by itself; it never pauses the game or takes the keyboard. The lit windows are the painting's own dark window shapes, found once per picture and remembered.
- **Works with:** `App` (decides when to show it), `Toasts` (shows it), `HarbourLooks` (the picture), `Daylight`, `BoatLighting` (overcast), `WaterLook` (the sea colour).
- **Keeps:** The harbour, the sun's height and the overcast at arrival; a cache of window spots per picture.
- **When it runs:** Only while the card is on screen; it is drawn once (and on resize), not every frame.
- **If you change it:** Keep it quiet and short; returning to a known harbour must keep the small card, and loading a game or going below must not show it.

### `src/ui/hat_badge.gd`

**Purpose:** A small HUD badge that shows when your captain's hat is in danger or has been lost.
- **What it does:** Checks the hat every frame. If the hat is at risk on deck it shows a fluttering hat, "Hold onto your hat!" and the H key. If the hat is lost it shows a faded hat with a question mark and "Hat missing". Otherwise it stays hidden. It can also pulse for a few seconds just after the hat blows away.
- **Works with:** `GameSession` (hat status), `HatArt` (draws the hat), `UiTheme` (colours), `Hud` (creates it), `App` (uses its message durations and asks it to pulse).
- **Keeps:** Only what it is showing right now and a small animation timer. Nothing is saved.
- **When it runs:** Always during play, as part of the HUD (hidden on the chart).
- **If you change it:** The on-screen hat warning changes, and so do the hat toast lengths (`WARNING_SECONDS`, `LOST_SECONDS`) and the "Hat overboard!" headline, which the game and the hat tests also use.

### `src/ui/haul_out_panel.gd`

**Purpose:** The haul-out dialog at a boatyard: lift the boat out, clean the bottom, and choose extra work.
- **What it does:** Shows the price of a haul-out, plus tick boxes for extra jobs (an engine or rig service when due, hard antifouling). When you confirm, it pays through `GameSession.haul_out()`, plays a short lift-and-scrub animation, asks the game to spend one day, and then says what was done, including +2 renown for your first haul-out. Steady Hands: the upgrade's name is shown in the chosen language.
- **Works with:** `GameSession`, `BoatCare`, `HaulOutScene` (the picture), `SessionLog`, `App` (opens it and spends the day).
- **Keeps:** The selected extras and the result of the haul-out while the dialog is open.
- **When it runs:** When you choose the haul-out at a yard that can lift boats.
- **If you change it:** Boat-care prices, the time spent ashore and the Captain's Log entry for haul-outs could be affected.

### `src/ui/haul_out_scene.gd`

**Purpose:** The little drawing of the boat being lifted out of the water in the haul-out dialog.
- **What it does:** Draws sky, water, quays and the travel lift (the crane that lifts boats) in code. The boat rises with `lift` and the weed on its bottom fades with `fouled`. Catamarans are drawn as two hulls. Water drips while she comes up.
- **Works with:** `HaulOutPanel`, which creates it and animates it.
- **Keeps:** How high the boat is, how dirty the bottom is, and whether it is a catamaran.
- **When it runs:** Only while the haul-out dialog is open.
- **If you change it:** Only the look of the haul-out picture changes. Gameplay is not affected.

### `src/ui/hud.gd`

**Purpose:** The on-screen overlay you see while playing: where you are, the clock, the route, the wind and warnings.
- **What it does:** Refreshes its text every frame from the game: the area and harbour, the clock and PAUSED badge, the planned route or voyage progress with ETA, the boat's condition, money and stores, and the wind. It shows weather warnings and the "press E" prompt, and it holds the hat badge, the aboard badge, the passage panel, the sailing panel, the chartplotter and the radar. On the chart it shows only the clock bar. Steady Hands: the right-hand column (route panel, Trip Details, weather warning) is stacked so a warning never moves Trip Details and takes the height its text needs; the route panel gives up width rather than run under the clock at a large interface size; the prompt steps right of the chartplotter and radar; "Moored at" / "Arrived at" are translated.
- **Works with:** `GameSession`, `Simulation`, `PortCatalog`, `HatBadge`, `AboardBadge`, `PassagePanel`, `SailingPanel`, `ChartPlotter`, `RadarPanel`, `App`.
- **Keeps:** Nothing of its own besides a cached route time estimate and whether it is in chart mode.
- **When it runs:** Always during play (part of the main app scene).
- **If you change it:** Everything the player reads at a glance changes. Several other panels also reuse its wind text (`Hud.describe_wind`).

### `src/ui/language_picker.gd`

**Purpose:** The first-launch question: English or Dansk?
- **What it does:** Shows a small dialog in both languages with one button per language. Picking one saves it in the settings and closes the dialog. Esc does nothing, because you must choose.
- **Works with:** `SettingsManager`, `Loc` (the language list), `App` (shows it once from the main menu).
- **Keeps:** Nothing. The choice is stored in the settings file, not in a save.
- **When it runs:** Only the first time the game starts, before a language has been chosen.
- **If you change it:** The first-launch experience changes. A bug here could block the main menu at first launch.

### `src/ui/loading_screen.gd`

**Purpose:** The game's own loading screen with the logo over a calm sea.
- **What it does:** Shows the logo, a tagline and an animated scene (waves, a lighthouse with a turning light, a bobbing sailboat) while it loads the harbour list, the routing charts (on a background thread) and the boat catalogue. It names each step, then fades into the main menu. Since I022 it always uses the main menu's deep navy, so the start matches the menu it fades into; Godot's boot splash before it is navy too, with the logo at its own size (sharp, not stretched).
- **Works with:** `UiTheme` (its night colours, whatever the hour), `PortCatalog`, `SeaRouter`, `VesselCatalog`, `App` (creates it).
- **Keeps:** Which step it is on and whether it has already been shown this run.
- **When it runs:** Once per launch, right after start-up (never without a screen, so never in tests).
- **If you change it:** Start-up time and the first impression of the game change.

### `src/ui/main_menu.gd`

**Purpose:** The title screen.
- **What it does:** Shows the buttons (New game, Continue, Load, Settings, Quit, and the developer guides and import buttons when available) and only reports which one you pressed. Continue is enabled only when a valid save exists, and it shows the slot, date and place of that save.
- **Works with:** `SaveManager`, `SettingsManager`, `SaveLoadMenu` (date format), `GameVersion`, `LegacySaves`, `DevGuides`, `App` (does the actual work).
- **Keeps:** Nothing of its own.
- **When it runs:** When the game shows the title screen.
- **If you change it:** Starting, continuing and loading games from the title screen could be affected.

### `src/ui/markdown_lite.gd`

**Purpose:** A small helper that turns Markdown text into the formatted text Godot can show.
- **What it does:** Converts headings, lists, bold, italics, code, links, tables and rules into BBCode (Godot's text formatting tags) for the developer guides viewer. It is not a full Markdown implementation.
- **Works with:** `DevGuidesMenu` (uses it), `UiTheme` (colours for code and links).
- **Keeps:** Nothing; it is a pure helper.
- **When it runs:** When the developer guides are opened (development builds).
- **If you change it:** Only how the developer guides look in the game changes. Players never see it.

### `src/ui/modal_panel.gd`

**Purpose:** The base for every pop-up dialog in the game.
- **What it does:** Gives each dialog a shared way to close, react to Esc, pick the button that gets keyboard focus, and ask the game to show a short notification.
- **Works with:** `ModalStack` (which shows the dialogs), and every dialog built on it (pause menu, settings, save/load and many more).
- **Keeps:** Only a link to the stack that holds it.
- **When it runs:** Whenever any dialog is open.
- **If you change it:** Every menu and dialog in the game is affected.

### `src/ui/modal_stack.gd`

**Purpose:** Keeps track of open dialogs so that only the top one is shown and Esc always goes back one step.
- **What it does:** Pushes new dialogs on top and hides the one below. When the top one closes it brings back the one underneath with keyboard focus. It also offers a ready-made "Are you sure?" confirmation.
- **Works with:** `ModalPanel`, `ConfirmDialog`, `App` (pauses the game while any dialog is open and shows their notifications).
- **Keeps:** The list of open dialogs.
- **When it runs:** Always (part of the main app scene).
- **If you change it:** Menu navigation, pausing during menus and confirmations everywhere could break.

### `src/ui/new_game_menu.gd`

**Purpose:** The new-game dialog where you choose your companion, the cat or the dog.
- **What it does:** Shows a preview and a short description of the chosen companion (the cat is preselected) and reports Start with the choice. Since I022 it also asks how forgiving the sea should be (the difficulty).
- **Works with:** `CompanionState`, `ShipCompanion` (the preview), `App` (starts the game).
- **Keeps:** The chosen companion kind until you press Start.
- **When it runs:** When you press New game on the title screen.
- **If you change it:** Who lives in your cabin at the start of a new game.

### `src/ui/passage_panel.gd`

**Purpose:** A compact panel on deck during long voyages, with fast-time buttons.
- **What it does:** Shows where the boat is, the day at sea, the weather outlook along the route, whether the stores will last, and boat care that is needed. Its buttons let time pass at 1, 4 or 12 hours per second, open the chart or save. When fast time stops by itself it says why (and how many fish nibbled meanwhile).
- **Works with:** `GameSession`, `Simulation` (passage clock), `Hud` (contains it), `BoatCare`, `Provisions`, `VoyageMap` (reuses its button labels).
- **Keeps:** Only cached outlook text and the latest "stopped" message.
- **When it runs:** Underway on voyages of 60 sm or more, when not at anchor.
- **If you change it:** Long passages and their fast-time controls are affected.

### `src/ui/pause_menu.gd`

**Purpose:** The in-game pause menu.
- **What it does:** Shows Resume, Captain's Log, Save, Load, Settings and Main menu, and only reports which was pressed. In development builds it adds a "Developer tests" button. Since I022 it has a Difficulty… button. I022: it also has Captain's Handbook (F1).
- **Works with:** `App` (carries out the choice), `DevTools`.
- **Keeps:** Nothing.
- **When it runs:** When you press Esc or the menu button during play.
- **If you change it:** Saving, loading and leaving the game from play could be affected.

### `src/ui/postcard_menu.gd`

**Purpose:** The Postcards from the Sea dialog, opened from the cabin's Q wheel (I022).
- **What it does:** Lets the player choose what the card shows, its words and its layout, shows the card as it will look, and says before starting that making and publishing it takes about two game hours and whether it earns renown. A card interrupted part-way comes back as it was, with the time left, and can be finished or thrown away. It also opens the scrapbook.
- **Works with:** `App` (spends the time), `GameSession` (the draft), `Pastimes`, `PostcardView`, `ScrapbookMenu`.
- **Keeps:** The subjects offered and the choices made.
- **When it runs:** While the dialog is open.
- **If you change it:** The two-hour notice must stay visible before the player starts.

### `src/ui/postcard_view.gd`

**Purpose:** Draws one postcard: the preview while making one, and each page of the scrapbook (I022).
- **What it does:** Paints a paper card in one of three layouts (classic, snapshot, banner) with the caption and the place it was sent from. The picture uses the game's own art: the harbour's landmark, the fish, the companion resting; for voyages, weather and evening light it paints a small sea and sky with a sailing boat.
- **Works with:** `PostcardMenu`, `ScrapbookMenu`, `Pastimes`, `HarbourLooks`, `FishArt`, `CompanionVisualSet`.
- **Keeps:** The card shown and its picture.
- **When it runs:** When a card is chosen or a page is turned.
- **If you change it:** Keep it to plain drawing (no shaders); the words come from `Pastimes` so they stay translated.

### `src/ui/provisions_menu.gd`

**Purpose:** The provisions locker: how much food and water is aboard and how long it lasts.
- **What it does:** Shows the days of food and water, their level and the total endurance, and explains where to buy more. In a harbour with a grocery store it offers a button to go there.
- **Works with:** `GameSession`, `Provisions`, `HarbourFacilities`, `App` (opens the grocery store).
- **Keeps:** Nothing; it re-reads the game while open.
- **When it runs:** When you use the provisions station in the cabin.
- **If you change it:** How the player sees and buys provisions.

### `src/ui/publish_menu.gd`

**Purpose:** The dialog for publishing a travel update online to turn renown into money.
- **What it does:** Shows your unpublished renown, the rate, the earnings and your money before and after, and asks you to confirm. The actual sale happens in `GameSession`.
- **Works with:** `GameSession`, `App` (publishes when confirmed).
- **Keeps:** Nothing.
- **When it runs:** When you choose "Publish travel update" from the Captain's Log or the work station.
- **If you change it:** How the player earns money from renown.

### `src/ui/radar_panel.gd`

**Purpose:** A small radar screen on deck that shows other ships nearby.
- **What it does:** Draws your boat in the centre, range rings and nearby ships coloured by danger, and writes up to three lines on the most important ones (how close they pass and what to do). You can zoom between 3, 6 and 12 sm. It appears when you turn it on, or by itself when a ship is a risk underway. It shows only underway, where its Q-menu item is: switched on at sea it goes away on mooring and comes back on the next voyage.
- **Works with:** `Simulation` (traffic risks), `GameSession`, `TrafficModel`, `Hud` (contains it), `App` (the action wheel switches it on).
- **Keeps:** Whether it is switched on and the zoom level (for this run only, not saved).
- **When it runs:** During play, on deck. It checks traffic a few times a second.
- **If you change it:** How players notice ships and avoid collisions.

### `src/ui/reel_dial.gd`

**Purpose:** The round dial you use when reeling in a fish (and the magic anchor).
- **What it does:** Draws a ring with a green target arc, a smaller "perfect" zone, a turning needle, the checks done and the line's remaining grip. It flashes after each press and treats a click like the action key.
- **Works with:** `FishingMenu` and `AnchorMenu` (which create it), `ReelTiming`/`TimingCheck` (the timing it draws), `SettingsManager` (reduce flashing).
- **Keeps:** Only a short flash timer.
- **When it runs:** While a reel-in or magic-anchor timing game is shown.
- **If you change it:** The look and feel of the fishing mini-game.

### `src/ui/rescue_dialog.gd`

**Purpose:** Tells you what happened after your boat was too damaged and you were rescued.
- **What it does:** Explains that a rescue crew towed you back, and shows the return harbour, the rescue fee and the money left. The rescue itself has already happened.
- **Works with:** `GameSession`, `PortCatalog`, `App` (shows it after a rescue).
- **Keeps:** The rescue details it was given.
- **When it runs:** Right after a rescue at sea.
- **If you change it:** Only the rescue message changes.

### `src/ui/sail_trim_panel.gd`

**Purpose:** The sail trim dialog: ease or sheet in the sails by hand, or let the crew do it.
- **What it does:** Offers a slider from Eased to Sheeted in, a sketch of the boat from above with the wind and the boom, and a word on how well the sails are trimmed with the speed effect in percent. Keys A/D change the trim, Space hands it to the crew, T or Esc closes. Changes apply at once.
- **Works with:** `GameSession` (stores the trim), `SailTrim` (the rules), `PropulsionState`, `UiTheme`, `App` (opens it).
- **Keeps:** Nothing of its own; the trim is in the game state.
- **When it runs:** Underway, when you press T (not at anchor).
- **If you change it:** How players control sailing speed.

### `src/ui/sailing_panel.gd`

**Purpose:** The panel on the right while underway with the numbers a skipper glances at.
- **What it does:** Shows speed, heading, the wind now, the sail trim, the next leg with a wind forecast, and the time and distance to the next turn or anchorage. It gently highlights the heading when the course changes, and it can be folded up.
- **Works with:** `GameSession`, `Simulation`, `WorldMap` (next turn), `Hud` (contains it, wind text), `SailTrim`, `SettingsManager`, `UiTheme`.
- **Keeps:** Whether it is folded (for this run only) and some cached forecast text.
- **When it runs:** During play, whenever the boat is underway.
- **If you change it:** The main sailing information on screen.

### `src/ui/sailmaker_menu.gd`

**Purpose:** The sailmaker shop at the boatyard.
- **What it does:** Offers two things: a rig and sail service (the same as the boatyard's, which makes the boat sail better) and new sailcloth colours (only a look; they do not change the speed). A cloth already bought for this boat can be put on again for free.
- **Works with:** `TradePanel` (its layout), `GameSession`, `BoatCare`, `HarbourTrades`, `SessionLog`, `App` (opens it and spends the time).
- **Keeps:** Nothing of its own.
- **When it runs:** When you visit the sailmaker in a harbour that has one.
- **If you change it:** Rig service prices and sail colours, which are saved per boat.

### `src/ui/save_load_menu.gd`

**Purpose:** The list of save slots for saving or loading a game.
- **What it does:** Shows each slot with its date, place and route. In save mode it saves to the chosen slot (asking before overwriting). In load mode it reports the chosen slot so the game can load it. The quicksave can be loaded here too.
- **Works with:** `SaveManager`, `GameSession`, `ModalStack` (overwrite question), `App`, `MainMenu` (uses its date format).
- **Keeps:** Whether it is in save or load mode.
- **When it runs:** When you choose Save or Load in the pause menu or title screen.
- **If you change it:** Saving and loading. A bug here could lose a player's progress.

### `src/ui/scrapbook_menu.gd`

**Purpose:** The scrapbook of postcards made (I022).
- **What it does:** Shows the cards one page at a time, newest first, with when each was sent; the arrow buttons or Left/Right turn the pages. With no cards yet it says how to make one.
- **Works with:** `PostcardView`, `GameSession` (the cards), `PostcardMenu` (opens it).
- **Keeps:** The page shown.
- **When it runs:** While it is open.
- **If you change it:** Keep a Close button; it always closes with Esc too.

### `src/ui/settings_menu.gd`

**Purpose:** The settings dialog, from both the title screen and the pause menu.
- **What it does:** Lets you change volumes (with test sounds), window mode, VSync, interface size, artwork style, sailing view, reduce flashing, lightning brightness, reduce motion, day/night interface light and language. Changes show at once; Apply saves them, and leaving without applying asks before undoing them. Since I022 it has a Wind slider with its own test sound (a few seconds of breeze). I022: a Tips check box turns the Academy's tips on or off. Steady Hands: the audio and display sections scroll when the screen is too short, so the title, status and buttons always stay in view.
- **Works with:** `SettingsManager`, `AudioManager`, `MusicDirector`, `SessionLog` (logs folder), `ModalStack`.
- **Keeps:** A copy of the last saved settings, to detect unsaved changes.
- **When it runs:** When you open Settings.
- **If you change it:** All player preferences, which are saved in the settings file.

### `src/ui/simple_panel.gd`

**Purpose:** A building kit for simple dialogs: a title, some text and a row of buttons.
- **What it does:** Builds a centred panel over a dimmed background in code and provides quick ways to add labels and buttons.
- **Works with:** `ModalPanel` (it builds on it), and many dialogs that use it (work, grocery, haul-out, trade shops, VHF and others).
- **Keeps:** Only references to its box and button row.
- **When it runs:** Whenever one of those dialogs is open.
- **If you change it:** The look and layout of many dialogs at once.

### `src/ui/sleep_menu.gd`

**Purpose:** The dialog where you choose how long to sleep.
- **What it does:** Lets you pick 1 to 12 hours (buttons or Left/Right keys), shows when you will wake, and reports the choice. It remembers the last duration.
- **Works with:** `SettingsManager` (remembers hours), `GameSession`, `Simulation` (wake time), `App` (does the sleeping).
- **Keeps:** The chosen number of hours.
- **When it runs:** When you go to the berth or choose Sleep from the chart.
- **If you change it:** How players skip time by sleeping.

### `src/ui/theme/ui_theme.gd`

**Purpose:** The game's look for all menus and panels, with a day mood and a night mood.
- **What it does:** Builds the colours and shapes of buttons, panels and text from a palette (parchment and brass by day, midnight blue and lantern amber by night). It follows the sun where the boat is: day until the middle of the evening twilight, night until the middle of the morning twilight, with an easy change of a few seconds in between (or it stays day or night if the settings say so). It no longer sits half-way through the whole twilight, where text and panel became the same grey, and text colours never mix: they switch at the middle of the change (Steady Hands). Other screens ask it for colours.
- **Works with:** `SettingsManager` (interface light), `GameSession`, `Daylight`, and nearly every screen that draws its own pictures.
- **Keeps:** The current day/night blend and the theme pieces it has built.
- **When it runs:** Always (an autoload: a script Godot starts automatically and that always exists).
- **If you change it:** The look of the whole interface changes.

### `src/ui/time_controls.gd`

**Purpose:** The Pause / 1× / 5× / 20× buttons in the clock bar.
- **What it does:** Lets you pause or speed up time, and keeps the buttons in step with the game's real state. The buttons never take keyboard focus, so they do not get in the way of movement keys.
- **Works with:** `GameSession` (pause and time speed), `SessionState` (the list of speeds), the HUD scene (where it sits).
- **Keeps:** Nothing of its own.
- **When it runs:** Always during play, in the HUD clock bar.
- **If you change it:** How players control the passing of time.

### `src/ui/time_passage.gd`

**Purpose:** The gentle fade-to-black with the date when you sleep or when dawn or dusk passes.
- **What it does:** Fades the screen to a dark blue, shows the date and weekday (and for sleep a clock counting forward hour by hour), lets the game do its work underneath, then fades back. Any key or click skips ahead.
- **Works with:** `App` (starts it for sleep and new light), `DayNightWatch`, `Loc` (date words), `VoyageMap` (uses its colour).
- **Keeps:** Only whether it is running and whether you skipped.
- **When it runs:** When you sleep or dawn/dusk arrives, with a screen. It is switched off in tests.
- **If you change it:** How time skips feel. The actual game time is decided elsewhere.

### `src/ui/toasts.gd`

**Purpose:** The short notifications that pop up and fade away by themselves.
- **What it does:** Shows a message in a small panel, at most three at a time, and fades it out after a few seconds. It works even while the game is paused, so menus can report results. Since I021 it can also show the arrival card: a picture of the harbour with two lines, fading on its own. Steady Hands / Golden Harbours: it also shows the Golden Harbour Moment card for a while (longer than a notice) before it fades.
- **Works with:** `App` (sends all notifications through it).
- **Keeps:** The messages currently on screen.
- **When it runs:** Always (part of the main app scene).
- **If you change it:** Every notification in the game is affected. Many tests read these messages.

### `src/ui/trade_panel.gd`

**Purpose:** The shared layout for harbour shops.
- **What it does:** Builds a shop window with a title, an introduction, a scrolling list of rows (name, description and a price button), your money and a Close button. It updates when your money or boat changes.
- **Works with:** `SimplePanel`, `GameSession`, and the shops built on it: `ChandleryMenu`, `SailmakerMenu`, `FishmongerMenu`, `CabinHomeMenu`.
- **Keeps:** The list of rows and their buttons.
- **When it runs:** While one of those shops is open.
- **If you change it:** All harbour shops change at once.

### `src/ui/trophy_menu.gd`

**Purpose:** The trophy board: your five best catches and your fishing record.
- **What it does:** Shows each trophy fish on a plaque with its picture, rarity and grade, and lists totals (caught, released, sold, sharks set free, best per species).
- **Works with:** `GameSession` (fishing record), `FishingCatalog`, `FishArt`, `CatchBadge`, `App` (opens it).
- **Keeps:** Nothing; it reads the fishing record.
- **When it runs:** When you look at the trophy board in the cabin.
- **If you change it:** Only how trophies are shown.

### `src/ui/ui_scale_layer.gd`

**Purpose:** Makes menus and panels follow the "interface size" setting.
- **What it does:** Scales its layer and stretches its direct children to fill the screen in scaled units, so layouts still fit. The game world is not scaled.
- **Works with:** `SettingsManager`, the app scene's HUD, modal and toast layers, the world map scene, and `MainMenu` (built on it).
- **Keeps:** Nothing of its own.
- **When it runs:** Always, wherever such a layer is used.
- **If you change it:** The size and fit of the whole interface.

### `src/ui/vhf_dialog.gd`

**Purpose:** A call on the VHF radio and your answer.
- **What it does:** Shows what you hear on channel 16 and what answering would ask of you, with Answer or Decline. Declining is always fine. Answering an assist call has the boat stand by for a while.
- **Works with:** `VhfRadio` (the call texts), `GameSession` (handles the answer), `App` (shows it and the result).
- **Keeps:** The call it shows.
- **When it runs:** When a radio call comes in and no other dialog is open.
- **If you change it:** How players respond to radio calls.

### `src/ui/voyage_map.gd`

**Purpose:** The illustrated atlas shown during fast-time long passages.
- **What it does:** Fades the boat view away and shows a map of the voyage: the route, the boat, start and destination, date, distance and arrival estimate. It has buttons for the passage speeds and "Take the helm". When the passage stops by itself it says why and offers "Back aboard" or "Sail on". While it shows, the boat scene and HUD are hidden and paused to save work.
- **Works with:** `Simulation` (passage clock), `GameSession`, `CabinWorldMap` (land shapes), `UiTheme`, `PassagePanel`, `TimePassage`, `App` (opens it).
- **Keeps:** The route as drawn and what it has hidden.
- **When it runs:** When a fast-time passage starts underway (with a screen, not in ordinary tests).
- **If you change it:** How long passages look and how you get back aboard.

### `src/ui/work_menu.gd`

**Purpose:** The remote-work dialog at the cabin's work station.
- **What it does:** Lets you choose 1 to 8 hours of work, shows the pay, the finish time and the food and water used, and reports the choice. It also offers "Publish travel update".
- **Works with:** `GameSession` (pay and limits), `Simulation` (time format), `Provisions`, `App` (does the work).
- **Keeps:** The chosen number of hours.
- **When it runs:** When you use the work station while moored in a harbour.
- **If you change it:** How players earn money by working.

## Automated test suites

### `tests/suites/test_academy.gd`

**Purpose:** Checks the Captain's Academy (I022).
- **What it does:** Checks the Handbook data (every page in a chapter, every link valid, every key a real binding, no key letters written into texts, all of it in Danish), search in English and Danish, the progress in the settings, the first new game's offer (closable, asked once, never on a loaded game), the First Voyage ticked off by real actions, the tips (never over a window or a warning, once, off in Settings, Read more) and the Handbook (F1, the pause menu, search, beginning the First Voyage again).
- **Works with:** `Academy`, `AcademyGuide`, `HandbookMenu`, `App`, `SettingsManager`.
- **Keeps:** Nothing (it resets the Academy's progress afterwards).
- **When it runs:** With the other suites (`test_runner.tscn`).
- **If you change it:** Only the tests change.

### `tests/suites/test_anchor_life.gd`

**Purpose:** Checks that a quiet evening at anchor feels cosy and that morning coffee works (revision 0.102b).
- **What it does:** Starts the real game, makes coffee in harbour (no reward), sails from Copenhagen towards Malmö and anchors. Then it checks the "settled" feeling (companion naps, one quiet message, warm evening light and cabin lamp), waking at anchor, the once-only morning-coffee Log moment (+2 renown), save/load without repeats, and that a fresh breeze ends the cosy mood.
- **Works with:** `GameSession`, `Simulation`, `AnchorLife`, `CookingMenu`, `ShipCompanion`, `SaveManager`, the app scene.
- **Keeps:** Nothing of its own; it just collects the anchor messages it sees during the test.
- **When it runs:** Only in tests (the test runner).
- **If you change it:** Only the automated checks change. If a check here starts failing, look at life at anchor, coffee or the companion's naps. It also takes screenshots named `0102b_*`.

### `tests/suites/test_anchorage.gd`

**Purpose:** Checks anchorage waypoints: marking a stop on the chart where the boat should anchor (Iteration 18).
- **What it does:** On the chart it marks a waypoint as an anchorage (button or M). Spots on land or in water that is too deep are refused, with a reason and a nearby spot offered instead. It sails there with Long Passage, checks that the boat stops and asks "Ready to drop anchor?" once, then anchors or sails on. It also checks save/load, changing course at sea, the Date Line and old saves.
- **Works with:** `WorldMap`, `GameSession`, `Simulation`, `SeaRouter`, `AnchoragePrompt`, `PlannedRoute`, `SaveManager`.
- **Keeps:** Nothing of its own; it just remembers the chosen anchorage spot.
- **When it runs:** Only in tests.
- **If you change it:** Only the checks change. A failure here points at the anchorage waypoints, the arrival question or how routes are saved.

### `tests/suites/test_anchorage_overlay.gd`

**Purpose:** Checks the chart's coloured anchorage zones: teal for the normal anchor, amber for the Magic Anchor (revision 0.105b).
- **What it does:** It checks that nothing is worked out at world zoom. Zoomed in on Antigua, only the visible tiles are worked out, within a small time budget per frame, and they are kept for later. The colours must match the anchoring rule, the Date Line near Fiji must work, and hovering must explain the spot. Waypoints placed in teal or amber zones (with and without the Magic Anchor) and dragged onto land are checked too.
- **Works with:** `WorldMap`, `MapView`, `AnchorageLayer`, `CoastalGeography`, `GameSession`.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests.
- **If you change it:** Only the checks change. Some checks measure speed, so a slow computer can make them fail. Screenshots are named `rb_*`.

### `tests/suites/test_atmosphere.gd`

**Purpose:** Checks the weather you hear and see aboard: wind, water, rain, lightning and thunder (Iteration 17).
- **What it does:** It checks that the sound files exist and say where they came from, and that the sound channels are set up right. Rain should match the weather, a gale should sound louder, and sound should be muffled in the cabin. Lightning should flash (gentler with the accessibility settings) and thunder should come later from far-off storms. On deck, wind streaks and raindrops are checked. Since I022 it checks that the wind plays on its own Wind bus, which feeds the muffled Outside bus.
- **Works with:** `WeatherAudio`, `AudioManager`, `WeatherFixtures` (made-up test weather), `WeatherVisuals`, `SettingsManager`, the app scene.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests.
- **If you change it:** Only the checks change. A failure points at weather sound, lightning or deck weather effects.

### `tests/suites/test_boat_care.gd`

**Purpose:** Checks boat care: slow wear, boatyard services, the haul-out, equipment upgrades and Passage Readiness (Iteration 14).
- **What it does:** It checks that weed grows on the hull day by day, the rig wears with the miles and the engine counts its hours, always predictably. Yards only offer the work they can do, and the price grows with the damage and the size of the boat. Upgrades have real effects but never make the boat faster. Readiness is only advice. It also loads an old save (format 11) and clicks through the Boat care, haul-out and Log panels.
- **Works with:** `BoatCare`, `GameSession`, `PassageReadiness`, `DevTools`, `BoatCareMenu`, `HaulOutPanel`, `CaptainsLogMenu`, `SaveManager`.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests.
- **If you change it:** Only the checks change. A failure points at wear, boatyard prices or old-save loading. Screenshots are named `14_*`.

### `tests/suites/test_boat_of_your_own.gd`

**Purpose:** Checks the harbour trades and making the boat your own (I020).
- **What it does:** It checks which harbours have a fishmonger, chandlery or sailmaker. It sells fish (never twice, and the grocery store underneath shows the new money at once), buys gear and cabin things (never below zero money), and orders sails in a new colour (a look only). Cabin things are placed on all four boats without blocking a station. It also checks that old and odd saves load, and that the Danish texts fit the screen. Since I021 it accepts that a long shop list scrolls: a row scrolled out of view is not counted as off screen. Since Operation Paperwork it also checks that the brass compass hangs in every cabin and is called "Kompas i messing" in Danish.
- **Works with:** `HarbourFacilities`, `HarbourTrades`, `TradePanel`, `GameSession`, `CabinDecor`, `SessionState`, `SettingsManager`.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests.
- **If you change it:** Only the checks change. A failure points at shops, money, sail colours or cabin decorations.

### `tests/suites/test_branding.gd`

**Purpose:** Checks the game's name, version number, fonts, save folder, and copying old Next Harbor saves.
- **What it does:** It checks that the game is called "Little Captain's Hat", that the version is 0.108a everywhere, and that the logo and icon files exist. It checks that saves live in the game's own folder and that the hand-lettered Patrick Hand font is used only for headings (Barlow for everything else). It also checks that old Next Harbor saves are copied (never moved or overwritten) into free save slots, including from the main menu's import button.
- **Works with:** `GameVersion`, `SaveManager`, `LegacySaves`, `MainMenu`, `ConfirmDialog`, `CaptainsLogMenu`, `Hud`, `SettingsManager`.
- **Keeps:** Nothing of its own (it makes a temporary pretend Next Harbor folder and removes it).
- **When it runs:** Only in tests.
- **If you change it:** Only the checks change. It checks the exact version ("0.108a", "0.108.1") and save format 12, so a new release means updating this test.

### `tests/suites/test_cabin_windows.gd`

**Purpose:** Checks the cabin windows and the softer water (I022).
- **What it does:** Checks that every window opening lies inside the Starling 33's wall art, that the windows sit over the walls and under the furniture, and that the view changes with where the captain stands, the side, the heading, the harbour, the hour and the weather. It also checks that the classic art and the other cabins are untouched, measures the cost of a redraw, and checks that the water's softness and the glass tint are separate. It takes screenshots from two viewpoints, at dusk, at night, underway, and of the deck water before and after.
- **Works with:** `CabinWindows`, `WaterLook`, `BoatArea`, `App`.
- **Keeps:** Nothing.
- **When it runs:** With the other suites (`test_runner.tscn`).
- **If you change it:** Only the tests change.

### `tests/suites/test_captains_log.gd`

**Purpose:** Checks the Captain's Log statistics and its panel (Iteration 006).
- **What it does:** It checks visited harbours, distance sailed and voyage records for arrivals, changes of course and rescues. The miles must come out the same in one big time step or many small ones, only the latest voyages are kept, and save/load and very old (version 7) saves must work. Then it opens the Log panel with L, tries its tabs and harbour filters, and opens it from the pause menu. Golden Harbours: the first-visit line may be part of the harbour moment card; it must appear exactly once.
- **Works with:** `GameSession`, `CaptainsLog`, `Simulation`, `SaveManager`, `CaptainsLogMenu`, `WeatherFixtures`.
- **Keeps:** Nothing of its own; it records the "voyage logged" messages it hears.
- **When it runs:** Only in tests.
- **If you change it:** Only the checks change. A failure points at the Logbook numbers or how they are saved.

### `tests/suites/test_captains_other_life.gd`

**Purpose:** Checks I022, The Captain's Other Life.
- **What it does:** Checks boat prices, that a new game owns only the starter boat, buying a boat (never twice, never below zero money, only at a boatyard), that old saves keep every boat, the three difficulty levels (starting money, food, costs, Danish names), changing the level during a game, and the New Game and pause menus that offer it. I022 pastimes: postcards (real subjects, two hours, kept when interrupted, renown once), the little game (2 to 4 hour sessions, points for the share worked, milestones, release, no repeated rewards), saves and old saves, the one clock through App (two hours of the world pass, an arrival interrupts a card and it is finished later) and the menus.
- **Works with:** `GameSession`, `SessionState`, `VesselCatalog`, `Difficulty`, `NewGameMenu`, `DifficultyMenu`, `App`.
- **Keeps:** Nothing.
- **When it runs:** With the other suites (`test_runner.tscn`).
- **If you change it:** Only the tests change.

### `tests/suites/test_captains_watch.gd`

**Purpose:** Checks the Captain's Watch: ship traffic, radar, collision warnings, anchor alarms and VHF radio calls (I019).
- **What it does:** It checks that other ships are always in the same places for the same time, stay on water and are not too many. It checks the closest-approach maths, and that collision warnings come early, once per ship, and wake you or stop Long Passage. It checks the anchor alarm levels and VHF calls: answering pays only once, even after a save and load. It also checks that the radar, switched on at sea, goes away on mooring and returns on the next voyage.
- **Works with:** `TrafficModel`, `Simulation`, `GameSession`, `RadarPanel`, `VhfRadio`, `AnchorState`, `SeaRouter`.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests. It is one of only two suites that switch on encounters at sea.
- **If you change it:** Only the checks change. A failure points at traffic, warnings or radio calls.

### `tests/suites/test_catamaran_cabin.gd`

**Purpose:** Checks the Halcyon 40 catamaran's cabin (Iteration 004b).
- **What it does:** It checks the saloon door to the deck and its prompt, and that the furniture drawing matches where you bump into things. It checks that the berths are a sensible size and that the player can walk into both hulls (really pressing the move keys). It also checks the nav station opens the chart, sleeping wakes you by the berth, and the companion's spots can be reached.
- **Works with:** the app scene, `BoatArea`, `BoatFixture`, the walkability test helper, `SleepMenu`, `ShipCompanion`.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests.
- **If you change it:** Only the checks change. Moving furniture or doors in the catamaran cabin can make it fail.

### `tests/suites/test_catch_and_cove_journey.gd`

**Purpose:** Plays one whole "Catch & Cove" day the way a player would (Iteration 13).
- **What it does:** It departs for Malmö, trolls a lure, lands a fish with the reel dial, and saves and loads. Then it anchors at the windlass, cooks the fish for supper, sleeps at anchor, raises the anchor and sails on, checking that a final save loads exactly. A second evening checks rough weather: no anchoring in a gale, and the anchor alarm wakes you in time.
- **Works with:** the app scene, `GameSession`, `Simulation`, `FishingMenu`, `AnchorMenu`, `CookingMenu`, the reel and walkability test helpers, `WindField`.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests.
- **If you change it:** Only the checks change. Because it uses so many systems, a change to fishing, anchoring, cooking or sleep can make it fail.

### `tests/suites/test_chart_and_pause.gd`

**Purpose:** Checks the chart's sidebar layout and the shared Pause button.
- **What it does:** It checks the chart sidebar (header, Course / Weather / Details tabs, footer): it stays in place on every tab, at 20× speed, with different interface sizes and in a smaller window. It also tests course editing, the zoom, centre and wind buttons, and dragging the map. Pause must freeze time, the voyage, the wind and the companion in the cabin, on deck and on the chart. Sleep must work while paused, and a game saved while paused must load paused.
- **Works with:** `WorldMap`, the HUD time bar, `GameSession`, `Simulation`, `SleepMenu`, `SettingsManager`, `SaveManager`.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests.
- **If you change it:** Only the checks change. Moving chart buttons or changing pause can make it fail.

### `tests/suites/test_chartroom_ui.gd`

**Purpose:** Checks the "Chartroom" look: one shared theme with a day mood and a night mood.
- **What it does:** It checks the theme's colours, fonts and contrast. It checks that Always day / Always night / Automatic are saved in settings (not in the save) and that Automatic follows the game's daylight, changing slowly. An open window must stay open when the mood changes. It also checks a calmer HUD, the chart's course panel, boat care, the fishing timing dial, and that colour tints follow the mood.
- **Works with:** `UiTheme`, `SettingsManager`, `Hud`, `WorldMap`, `BoatCareMenu`, `FishingMenu`, `ReelDial`.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests.
- **If you change it:** Only the checks change. Changing theme colours or HUD layout can make it fail.

### `tests/suites/test_coastal_depth.gd`

**Purpose:** Checks the worldwide coast map, sea depths and anchoring rules, without starting the game (revision 0.105b).
- **What it does:** It checks that the detailed coast map loads, and that the router can reach close-in water through a short, safe path. It uses made-up coasts and depth files to test tricky cases. Depths must be labelled "GAME ESTIMATE", always the same for the same place, smooth and varied. It checks that shelter depends on the wind but depth does not, the anchoring rules, and that six sailing areas around the world each have a usable anchorage.
- **Works with:** `CoastalGeography`, `DepthService`, `DepthData`, `SeaRouter`, `AnchorSite`, `GameSession`.
- **Keeps:** Nothing of its own (it writes two small temporary test files).
- **When it runs:** Only in tests.
- **If you change it:** Only the checks change. A failure points at coast data, depth estimates or the anchoring rule.

### `tests/suites/test_cockpit_ui.gd`

**Purpose:** Checks the cockpit instruments: the sailing panel, the chart plotter and the action wheel (Iteration 17).
- **What it does:** Sailing towards Las Palmas, it checks that the sailing panel shows speed, heading, wind, the next leg and the next turn (estimates are labelled as estimates). The panel must fold up, and must not cover other panels. A course change of more than 5° flashes briefly. The chart plotter (P) shows the coast around the boat only on deck and underway, without building the big world chart. The action wheel (Q) shows the right actions on deck and in the cabin, works with keyboard and mouse, and nothing behind it reacts.
- **Works with:** `SailingPanel`, `ChartPlotter`, `ActionWheel`, `Hud`, `WorldMap`, `GameSession`, `Simulation`.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests.
- **If you change it:** Only the checks change. Changing panel texts or wheel actions can make it fail.

### `tests/suites/test_companion_art.gd`

**Purpose:** Checks the cat and dog pictures and how they behave (Iteration 004b, with new art since Iteration 13).
- **What it does:** It checks the pose images (resting, sleeping, alert, stretching) for cat and dog, and that the owner's original cat drawings in `Visuals/Cat/` are never changed. It checks that white paper backgrounds are removed, and that the poses change now and then without flickering. It also checks walking up to and petting the pet (glow outline, purr), fallbacks when an image is missing, swapping in a new image through data only, all boats, and that poses are not saved.
- **Works with:** `CompanionVisualSet`, `ShipCompanion`, `NewGameMenu`, `CompanionState`, `AudioManager`, `SaveManager`, the walkability test helper.
- **Keeps:** Nothing of its own (it writes a temporary test picture and deletes it again).
- **When it runs:** Only in tests.
- **If you change it:** Only the checks change. It will fail if anyone edits the owner's original cat drawings, because their fingerprints are checked.

### `tests/suites/test_companion_deck.gd`

**Purpose:** Checks the pet coming up on deck, the anchor signals and the boat's night lights (Iteration 18).
- **What it does:** On all four boats it checks three safe resting places on deck, and that the pet follows the captain up and down after a short delay, never walking off the boat. It goes below when the boat sets off or the wind rises, and its place is saved. At anchor the black ball, the anchor line and the buoy show. At night it checks the lights: white anchor light at anchor, red/green/stern lights underway (correct sides in all eight view directions), and none when moored.
- **Works with:** `DeckCompanionSpots`, `ShipCompanion`, `GameSession`, `BoatLighting`, `SailRig`, `SaveManager`, the app scene.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests.
- **If you change it:** Only the checks change. Moving deck fittings or the deck outline can make it fail.

### `tests/suites/test_companion_remarks.gd`

**Purpose:** Checks the kind words when petting the companion.
- **What it does:** Checks that cats and dogs have their own lines, that the same line never comes twice in a row, the "good girl"/"good boy" lines for a named dog, that a name with Danish letters is kept exactly, the Danish lines and switching language, petting a cat and a dog in the cabin (the reaction still plays, a remark comes, not again at once, a different one later), the hands-full rule, and that saves are unchanged.
- **Works with:** `CompanionRemarks`, `ShipCompanion`, `BoatArea`, `GameSession`, `SettingsManager`.
- **Keeps:** Nothing.
- **When it runs:** In the test runner (`--only=companion_remarks`).
- **If you change it:** Only the test; the remarks' wording is checked by its English keys.

### `tests/suites/test_cozy_patch.gd`

**Purpose:** Checks the small patch after 0.105b: petting the cat while she walks, fish pictures on the trophy board, and the Dreamer's Map colours.
- **What it does:** It pets Snøvs while she walks onto the deck, just after she arrives, and while she walks back down. The walk pauses, she reacts once, and she still ends up in the right place. It checks that each trophy shows its own fish picture, that empty slots stay empty, and that a new catch shows at once. The Dreamer's Map must have its painted colours, but the navigation chart must not.
- **Works with:** `ShipCompanion`, `DeckCompanionSpots`, `TrophyBoard`, `FishArt`, `FishingState`, `WorldMap`, `GameSession`.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests.
- **If you change it:** Only the checks change. The walks are stepped in game time, without waiting real frames, and the follow-the-captain timer is held still while she walks out, so the result no longer depends on the computer's speed.

### `tests/suites/test_cozy_polish.gd`

**Purpose:** Checks the "Cozy Polish" round of navigation and comfort fixes.
- **What it does:** It checks routes through the Kiel Canal, Suez (with Bab-el-Mandeb) and Panama, and around Stockholm, including saving in the middle of a canal. It checks that the chart's widest zoom stays on the map, and that a stray click no longer adds a waypoint. Floating things should pass the boat towards the stern, and the Q menu should have its new labels and tick marks. Coffee and the hat take your hands, and every boat has a cup holder. It also checks the remembered sleep length, pins for visited harbours, smaller panels, the loading screen, and coffee in saves.
- **Works with:** `SeaRouter`, `WorldMap`, `MapView`, `WaterLife`, `ActionWheel`, `CoffeeMug`, `GameSession`, `SleepMenu`, `SettingsManager`, `LoadingScreen`, `SessionState`.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests.
- **If you change it:** Only the checks change. It also checks that the save format is still 12, so raising the save format means updating this test.

### `tests/suites/test_data_model.gd`

**Purpose:** Checks the basic building blocks: harbours, distances, map projection and the saved game state.
- **What it does:** It checks that about 150 or more harbours load, that the distance from Copenhagen to Kiel is about 116 sm, and that the map turns positions back and forth correctly. It saves a game state (with a planned route) as text and loads it back unchanged. Broken data is refused as a whole, and planning a route works.
- **Works with:** `PortCatalog`, `GeoMath`, `MapProjection`, `SessionState`, `GameSession`.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests (it is the first suite in the list).
- **If you change it:** Only the checks change. A failure here usually means saving and loading is broken.

### `tests/suites/test_denmark_views.gd`

**Purpose:** Takes pictures of the detailed Danish waters on the chart and at sea (Iteration 14).
- **What it does:** It shows the chart at several zoom levels over Denmark and checks that the detailed Danish map is drawn. It plots a course from Copenhagen around Zealand to Svendborg, sails it, and anchors near the coast. Then it visits the boatyard on Svendborg's quay. The checks are light; the screenshots are the main point.
- **Works with:** `WorldMap`, `MapView`, `SeaRouter`, `GameSession`, `Simulation`, `BoatyardMenu`, `HarbourFacilities`.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests (the pictures only when the run saves screenshots).
- **If you change it:** Only the checks and the `14_*` screenshots change.

### `tests/suites/test_dev_guides.gd`

**Purpose:** Checks the developer guides in `DEV_GUIDES/` and the in-game guide reader (Iteration 004b).
- **What it does:** It checks that every guide file exists, and that every link and file path written in the guides and main documents really exists. It checks that the simple Markdown-to-text converter works. It opens the guide reader from the main menu, picks a guide, scrolls and closes it. When the guides are missing, the feature hides itself without errors.
- **Works with:** `DevGuides`, `DevGuidesMenu`, `MarkdownLite`, `MainMenu`.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests.
- **If you change it:** Only the checks change. It fails when a guide or document gets a broken link or names a file that does not exist, so keep the docs tidy.

### `tests/suites/test_diagnostics.gd`

**Purpose:** Checks the diagnostic session log, a small record file the game writes while you play.
- **What it does:** It checks that each session writes one file with one record per line, starting with the game version. The file must record events like saves, loads, the hat, achievements, money and errors. It must not contain personal data like your user name, and the game must play exactly the same with or without it. The number and size of the files are limited.
- **Works with:** `SessionLog`, `GameSession`, `SaveManager`, `GameVersion`, `Simulation`.
- **Keeps:** Nothing of its own (it uses its own temporary log folder and cleans it).
- **When it runs:** Only in tests.
- **If you change it:** Only the checks change. It checks the exact game version ("0.108a") and save format (12), so a new version number means updating this test.

### `tests/suites/test_eight_directions.gd`

**Purpose:** Checks that the deck view turns to the nearest of eight compass directions as the boat sails (Iteration 13).
- **What it does:** It checks the rule for picking the nearest direction, including the "stickiness" that stops the view flipping back and forth. On deck, it checks that the bow points the right way on screen for all eight directions, and that turning is smooth. The W key must still walk up the screen, the camera must follow the captain on a big boat, all four boats must work, and the fixed view setting must still work.
- **Works with:** `BoatArea`, `SettingsManager`, `GameSession`, `Simulation`, the app scene.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests.
- **If you change it:** Only the checks change. It waits in real time for the camera to turn, so timing changes can affect it. Screenshots are named `13_view_*`.

### `tests/suites/test_fishing.gd`

**Purpose:** Checks fishing basics: the rod, lures, fish from data, bites, keeping and selling, and the trophy board (Iteration 13).
- **What it does:** It checks the fish and lure data. It checks that bites come on a fixed schedule (the same no matter how time is stepped), that each fish is kept only once, and that rewards are paid only once. When the cool box is full, the fish goes back. It also checks selling and buying lures, saving the catch, the rod and trophy board on every boat, the fishing panel with the reel dial, a missed bite, trolling while sailing, and the trophy board after save/load.
- **Works with:** `FishingCatalog`, `FishingState`, `GameSession`, `FishingMenu`, `TrophyMenu`, `SaveManager`, the reel and walkability test helpers.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests.
- **If you change it:** Only the checks change. A failure points at fishing rules, fish data or the rod and trophy stations.

### `tests/suites/test_fishing2.gd`

**Purpose:** Checks "Fishing 2.0": the reel-in dial, fish sizes and grades, the fish pictures, keep rules, sharks and junk (Iteration 18).
- **What it does:** It checks the dial rules: how many good presses each rarity needs, Perfect hits, forgiving misses, and fairness for careful and sloppy players. It checks weights and Bronze/Silver/Gold grades, and that every fish and piece of junk has its own picture, which blinks and flicks its tail (but stays still with Reduce motion), and that two fish never blink in step over thirty seconds. It checks keep preferences, that sharks are always released and junk thrown away, reaching the rod with R from anywhere, saves, and fishing at anchor and in fast time.
- **Works with:** `ReelTiming`, `FishingCatalog`, `FishArt`, `FishPortrait`, `FishingMenu`, `CatchBadge`, `GameSession`, `Simulation`, `SettingsManager`, the reel test helper.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests.
- **If you change it:** Only the checks change. Changing the dial's speed, arcs or fish data can make it fail.

### `tests/suites/test_galley_and_anchor.gd`

**Purpose:** Checks the galley stove and the anchor (Iteration 13, "The Cove").
- **What it does:** Checks the anchor's holding rules. Then, in the real game, it cooks meals from fish and groceries, follows the rule that the stove stays off when it is too rough underway, anchors near Malmö, lets the anchor drag in rising wind, sleeps at anchor and saves/loads while anchored.
- **Works with:** `GameSession`, `Simulation`, `AnchorSite`, `AnchorState`, `CookingMenu`, `AnchorMenu`, `SaveManager`, the app scene.
- **Keeps:** Nothing of its own; it uses save slot 3 for a short time and deletes it afterwards.
- **When it runs:** Only in tests.
- **If you change it:** Nothing in the game changes, but changes to cooking, anchoring, dragging or the windlass and stove positions on any boat may make it fail.

### `tests/suites/test_gameplay_flow.gd`

**Purpose:** Plays the whole game from start to finish, like a player using keys and mouse clicks.
- **What it does:** Tests the main menu, a new game, walking and bumping into things, prompts, the chart (zoom, pan, plotting and waypoints), stairs between cabin and deck, the pause menu, settings, saving/loading and Continue. Then it sails a first voyage to Kiel with a gale warning and a change of course, and ends by pressing Quit. Steady Hands: the companionway round trip check reports where the player stood and what the prompt said, to diagnose a rare failure. The companionway round trips move the ship's companion aside when it sits at the hatch (it used to get petted instead, an intermittent failure), and the "no teleport" check allows the distance the boat really sails while the chart opens.
- **Works with:** The app scene, `GameSession`, `Simulation`, `SaveManager`, `SettingsManager`, `SeaRouter`, `WeatherFixtures`, `MainMenu`, `WorldMap`, `PauseMenu`, `SaveLoadMenu`.
- **Keeps:** Nothing of its own (test save slots and a test settings file).
- **When it runs:** Only in tests, as the very last suite, because it quits the program.
- **If you change it:** Nothing in the game changes. It is the widest check, so almost any change to menus, controls, the chart or saves can make it fail.

### `tests/suites/test_golden_harbours.gd`

**Purpose:** Checks the Golden Harbour Moments.
- **What it does:** Sails real voyages to harbours never visited before and checks that the first arrival shows one illustrated card (with the name, "First visit" and the Captain's Log line, and no separate Log notice), that a click puts it away, that a known harbour keeps the small card, and that a second visit shows no card. Loading a game in a new harbour and going below and back show nothing. It also checks the light for the hour (day, dusk in Danish with the stamp in Danish, night), that the card stays inside the screen, and that the painting's windows are found quickly and remembered. It takes the day, dusk and night screenshots.
- **Works with:** `App`, `HarbourMoment`, `Toasts`, `GameSession`, `Simulation`, `SaveManager`.
- **Keeps:** Nothing (window size, language and automatic time are restored).
- **When it runs:** With the other suites (`test_runner.tscn`).
- **If you change it:** Only the tests change.

### `tests/suites/test_harbour_chart.gd`

**Purpose:** Checks that the chart stays clear and quick with many harbours.
- **What it does:** Checks that only important harbours show when zoomed far out and more show when zoomed in. It checks that names never overlap, that harbour search finds and zooms to a harbour, and that typing in the search box doesn't move the chart. It also times the chart's layout with up to 1,000 made-up harbours.
- **Works with:** `WorldMap`, `MapView`, `PortCatalog`, `PortData`, the app scene.
- **Keeps:** A small table of timing results that it prints.
- **When it runs:** Only in tests.
- **If you change it:** Nothing in the game changes; changes to harbour markers, labels, search or the harbour list may make it fail.

### `tests/suites/test_harbour_life.gd`

**Purpose:** Checks harbour life: walking ashore, the harbour services, Go Ashore outings and the course-facing deck view (Iteration 12).
- **What it does:** Checks which harbours have a grocery, a boatyard and haul-out (for example, Lohals has no boatyard). On every boat it checks that you can walk down the gangplank to the pontoon and back. It also checks that objects light up instead of circles, that Go Ashore events cost and pay once, that the gangplank comes in when you sail, and that saving ashore works. Finally it checks that underway the deck can turn so the bow points along the course. Since I021 the small new harbours (Dingle, Ísafjörður, Symi, Essaouira, St Helena) are on the list of harbours without a boatyard.
- **Works with:** `HarbourFacilities`, `ShoreEvents`, `GoAshoreMenu`, `BoatArea`, `Interactable`, `GameSession`, `Simulation`, `SaveManager`, `SettingsManager`, the walkability helper, the app scene.
- **Keeps:** Nothing of its own (uses save slot 3 and deletes it).
- **When it runs:** Only in tests.
- **If you change it:** Nothing in the game changes; changes to harbour services, pontoon layouts, shore events or the course view may make it fail.

### `tests/suites/test_harbours.gd`

**Purpose:** Checks every harbour in the harbour catalogue (the list of all harbours).
- **What it does:** Checks that every harbour has a unique, well-formed id and a complete record, that it lies on a coast inside the chart, and that it can reach open water. It also checks that every harbour can sail to its nearest original harbour, and it tries sample voyages (coastal, island hopping, offshore, narrow straits) and the harbour search. Since I021 it also knows the new sea areas (North America, West Africa, South Atlantic, Indian Ocean, Southeast Asia).
- **Works with:** `PortCatalog`, `PortData`, `SeaRouter`, `NavGrid`, `GeoMath`.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests (no game window needed).
- **If you change it:** Nothing in the game changes; adding or moving harbours or changing the sea map can make it fail.

### `tests/suites/test_hat.gd`

**Purpose:** Checks the captain's hat: hanging it up, wearing it, carrying it, losing it and buying a new one.
- **What it does:** Checks the hat hook and the H key, how strong wind and gusts strain a worn hat on deck, the warning before it blows away, and that the result is the same at any time speed and after save/load. It also checks the €15 hat at the grocery, old saves, and the hat on all boats and on the player in the real game.
- **Works with:** `GameSession`, `Simulation`, `HatState`, `HatConfig`, `HatStory`, `HatBadge`, `SaveManager`, `WeatherFixtures`, the app scene.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests.
- **If you change it:** Nothing in the game changes; changes to the hat rules, prices, save format or hook positions may make it fail.

### `tests/suites/test_joy_journey.gd`

**Purpose:** Plays the Captain's own example trip, with fishing, anchoring and sailing together, in 18 steps.
- **What it does:** Marks an anchorage waypoint on the way to Gothenburg and trims the sails by hand. Then it trolls, lands a fish and lets it go, uses Long Passage time until the anchorage, drops the anchor, makes coffee, and lets the companion join on deck. Finally it saves, loads, raises the anchor and sails on to Gothenburg. After loading, nothing may happen twice.
- **Works with:** `WorldMap`, `GameSession`, `Simulation`, `FishingMenu`, `AnchoragePrompt`, `SaveManager`, the reel helper (`tests/helpers/reel.gd`), the app scene.
- **Keeps:** Nothing of its own (uses save slot 3 and deletes it).
- **When it runs:** Only in tests.
- **If you change it:** Nothing in the game changes; changes to fishing, anchorages, Long Passage, the companion or saves may make it fail.

### `tests/suites/test_life_aboard.gd`

**Purpose:** Checks everyday life aboard: the cat or dog, sleeping, the chart panel and the sails.
- **What it does:** Checks choosing a cat or dog for a new game, where it rests, its schedule and petting it (with sound). It also checks the sleep dialog from the berth and the chart, waking early for a weather warning or on arrival, and that the chart panel stays still. Finally it checks the helm's sail check, gentle sail motion, the spinnaker's shape, and saving the companion, including in old saves.
- **Works with:** `NewGameMenu`, `SleepMenu`, `WorldMap`, `SailRig`, `ShipCompanion`, `CompanionState`, `AudioManager`, `GameSession`, `SaveManager`, `WeatherFixtures`, the app scene.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests (it boards the Wing 33, `starling_33`, because its walks were written for that cabin).
- **If you change it:** Nothing in the game changes; changes to the companion, sleeping, the chart sidebar or sail drawing may make it fail.

### `tests/suites/test_lighting.gd`

**Purpose:** Checks day and night light (Iteration 17).
- **What it does:** Checks the sun's height for the boat's place and season (including the midnight sun) and the order night, dawn, day, dusk. On every boat it checks warm cabin lamps and shadows at night and daylight by day. It also checks deck, harbour and navigation lights, and that the light changes gently at Long Passage speed and right away after loading.
- **Works with:** `Daylight`, `BoatLighting`, `Interactable`, `GameSession`, `Simulation`, the app scene.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests.
- **If you change it:** Nothing in the game changes; changes to lighting colours, lamps or the sun calculation may make it fail.

### `tests/suites/test_living.gd`

**Purpose:** Checks earning and spending money: remote work and the grocery store.
- **What it does:** Checks remote work in harbour (1–8 hours, €25 per hour, refused at sea) and grocery prices (€10 for each missing day of food plus water, the same in every harbour). It also checks that repairs cost their quote, that money and stores survive save/load, and that the work station and grocery store open on every boat.
- **Works with:** `GameSession`, `Simulation`, `SaveManager`, `WorkMenu`, `GroceryMenu`, `WeatherFixtures`, the app scene.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests.
- **If you change it:** Nothing in the game changes; changes to pay, prices, starting money or station positions may make it fail.

### `tests/suites/test_living_world.gd`

**Purpose:** Checks the "living little world" look: the sailor, the water and the drawn boats.
- **What it does:** Checks that the sailor swings their arms when walking and that harbour water moves gently, with the right water type for each harbour. It checks the illustrated deck and cabin of every boat, waves that follow the wind underway, and that the camera eases out when leaving harbour and back in on arrival. The arm-swing check walks on the open foredeck and is measured by distance: from the start spot the sailor walked into deck fittings after less than one stride, which made it fail.
- **Works with:** `WaterLife`, `HarbourArt`, `SailorDrawing`, `VesselVisual`, `BoatArea`, `SettingsManager`, the app scene.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests.
- **If you change it:** Nothing in the game changes; changes to the art, water effects or camera framing may make it fail.

### `tests/suites/test_localization.gd`

**Purpose:** Checks the English and Danish languages.
- **What it does:** Checks that every English text has a Danish translation that keeps its placeholders (spots where numbers or names are filled in). It also checks numbers, money, dates and compass points in each language, and that the first start asks for the language only once. Finally it checks that the Settings switch works at once, that Danish text fits on screen, that the boat's lighting is found aboard in Danish, and that saves are the same in both languages.
- **Works with:** `Loc`, `SettingsManager`, `LanguagePicker`, `GameSession`, `Simulation`, `SaveManager`, `locale/messages.pot`, `locale/da.po`, the app scene.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests (with sea encounters switched on by the test runner).
- **If you change it:** Nothing in the game changes; adding new text without a Danish translation will make it fail.

### `tests/suites/test_long_passage.gd`

**Purpose:** Checks Long Passage time (very fast time on long voyages) and ocean voyages.
- **What it does:** Checks that a voyage ends the same in fast time as in normal time, and that fast time stops for low stores, a bite or arrival. It also checks passage stores for each boat, the readiness advice before a long passage, and saving just past the Date Line. Finally it checks Captain's Log "firsts" in the Pacific and the Long Passage panel on deck.
- **Works with:** `Simulation`, `GameSession`, `PassageReadiness`, `VesselCatalog`, `Provisions`, `SaveManager`, `Hud`, the app scene.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests.
- **If you change it:** Nothing in the game changes; changes to time speeds, stops, stores or world "firsts" may make it fail.

### `tests/suites/test_magic_anchor.gd`

**Purpose:** Checks the Magic Anchor and anchoring with the engine stopped.
- **What it does:** Checks the shared timing dial (also used by the fishing reel) and buying the Magic Anchor at the chandlery (it stays with the captain on every boat). It also checks setting it offshore with one to three good turns depending on the wind, misses, cancelling and retrying, and dragging in a gale. Finally it checks that anchoring stops the engine, and saving/loading at anchor.
- **Works with:** `TimingCheck`, `ReelTiming`, `MagicAnchorDeployment`, `AnchorMenu`, `TradePanel`, `HarbourTrades`, `BoatCareMenu`, `AnchorSite`, `GameSession`, `SaveManager`, the app scene.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests.
- **If you change it:** Nothing in the game changes; changes to the anchor, the dial, prices or the engine rules may make it fail.

### `tests/suites/test_navigation_views.gd`

**Purpose:** Checks the cabin's framed world map ("Dreamer's Map") and the working chart.
- **What it does:** Checks that every cabin has a world map you can walk to. On the Dreamer's Map it checks that there is no wind or weather, and that searching and harbour stories work. "Imagine this voyage" must name real harbours along the way and change nothing. It also checks that "Plan it at the chart table" opens the real chart, that the chart opens around the boat, and that underway it shows the next turn.
- **Works with:** `WorldMap`, `MapView`, `VoyageDaydream`, `CabinWorldMap`, `HighlightResolver`, `SeaRouter`, `WeatherModel`, `GameSession`, the app scene.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests.
- **If you change it:** Nothing in the game changes; changes to the chart's views, the daydream text or wind arrows may make it fail.

### `tests/suites/test_objectives.gd`

**Purpose:** Checks sailing objectives and renown (ry).
- **What it does:** Checks the list of objectives (including the generated ones) and that renown is paid once when a voyage ends. Repeatable objectives pay again only on a new voyage. A lost boat earns only for its miles, and saving, loading and old saves never pay twice. It also checks the Objectives tab in the Captain's Log.
- **Works with:** `ObjectiveCatalog`, `ObjectiveProgress`, `CaptainsLog`, `CaptainsLogMenu`, `GameSession`, `Simulation`, `SaveManager`, `WeatherFixtures`, the app scene.
- **Keeps:** A list of the renown awards it has seen during the run.
- **When it runs:** Only in tests.
- **If you change it:** Nothing in the game changes; changing rewards, objectives or the save format may make it fail.

### `tests/suites/test_presentation.gd`

**Purpose:** Checks small presentation touches on deck and on arrival in harbour.
- **What it does:** Starts the real game and checks that fenders hang out in harbour and are stowed at sea (on all four boats), that the sails and boom are drawn above the captain and turn see-through when the captain stands under them, that the harbour preview lists only real services, and that the short docking scene on arrival can be skipped and counts the arrival only once.
- **Works with:** the app scene, `GameSession`, `Simulation`, `SaveManager`, `FenderStowage`, `SailRig`, `HarbourFacilities`, `BoatArea`.
- **Keeps:** Nothing of its own; it uses save slot 3 briefly and deletes it.
- **When it runs:** Only in tests.
- **If you change it:** Only the safety net changes; if it fails, fenders, the rig drawing or the docking arrival may look wrong in the game.

### `tests/suites/test_publishing.gd`

**Purpose:** Checks that publishing a travel update turns renown into money correctly.
- **What it does:** Checks that unpublished renown is paid out at the set rate (€2 per renown by default) in harbour only, never twice, that lifetime renown is kept, that it survives save and load, and that remote work and buying provisions still work. Then it clicks through the publish buttons in the Captain's Log and the work dialog in the real game.
- **Works with:** `GameSession`, `Simulation`, `SaveManager`, `ObjectiveCatalog`, `CaptainsLogMenu`, `PublishMenu`, `WorkMenu`.
- **Keeps:** Nothing of its own; it uses save slot 2 briefly and deletes it.
- **When it runs:** Only in tests.
- **If you change it:** Only the safety net changes; if it fails, players might be paid wrongly for renown.

### `tests/suites/test_reassessment.gd`

**Purpose:** Checks when the boat decides to switch between sailing and motoring after a change.
- **What it does:** Checks that after a change of course, or when you press "Check sail configuration" at the helm, the boat can switch between sails and engine at once in clearly good or bad wind, but still respects the minimum time per mode so it never flips back and forth. It also checks the helm's explanation messages.
- **Works with:** `PropulsionController`, `PropulsionState`, `VesselProfile`, `WindField`, `GameSession`, `Simulation`, the app script's `describe_reassessment`.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests.
- **If you change it:** Only the safety net changes; if it fails, the boat may switch engine and sails at odd times.

### `tests/suites/test_regions.gd`

**Purpose:** Checks the detailed Danish sea chart and how it fits into the world chart.
- **What it does:** Checks that the detailed Danish (and European) charts are loaded, that inland towns are land and straits are open water, that every Danish harbour has a way out to sea, that voyages through Danish waters route sensibly, and that a saved boat that now lies on land is moved to the nearest water instead of being lost. It also measures loading and routing speed and checks that the chart shows the detailed coast when zoomed in.
- **Works with:** `SeaRouter`, `NavGrid`, `PortCatalog`, `GameSession`, `AnchorSite`, `FishingCatalog`, `MapView`, `WorldMap`.
- **Keeps:** Nothing of its own; it prints timing measurements.
- **When it runs:** Only in tests.
- **If you change it:** Only the safety net changes; if it fails, Danish routes, harbour approaches or old saves may be affected.

### `tests/suites/test_route_wrap.gd`

**Purpose:** Checks that a planned route stays visible while you pan the world chart east or west.
- **What it does:** Plots long routes (Middelfart to Papeete, also with waypoints, and Papeete to Auckland across the Date Line), then pans the chart round the globe step by step and checks that the route is drawn wherever it is in view, never jumps across the map, and is not changed by panning. It also checks the course line underway and the daydream route on the Dreamer's Map.
- **Works with:** the app scene, `WorldMap`, `MapView`, `GameSession`, `PortCatalog`.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests (the pixel checks only when the game is actually drawn on screen).
- **If you change it:** Only the safety net changes; if it fails, routes may vanish from the chart while panning.

### `tests/suites/test_routing.gd`

**Purpose:** Checks that sea routes never cross land and reach every harbour.
- **What it does:** Checks that the route finder (the part that plans a course around coasts) finds valid routes between all European harbours and from Copenhagen to every harbour abroad, uses the real straits (Gibraltar, Dover, Øresund, Great Belt, Bonifacio, Panama), crosses the Date Line the short way, rejects waypoints on land, and fails safely for impossible routes. Each route is also checked against the coastline as the chart draws it.
- **Works with:** `SeaRouter`, `PortCatalog`, `GeoMath`, `PlannedRoute`, `MapProjection`, `NavGrid`, `WorldLand`, `GameSession`.
- **Keeps:** Nothing of its own; it loads the drawn land shapes once for its own checks.
- **When it runs:** Only in tests.
- **If you change it:** Only the safety net changes; if it fails, courses may cross land or some harbours may become unreachable.

### `tests/suites/test_sail_trim.gd`

**Purpose:** Checks the sail trim feature.
- **What it does:** Checks that the best trim follows the wind angle (in tight close-hauled, eased on a run, a bit flatter in strong wind), that the effect is modest (at most 6 % faster or 10 % slower), never switches the engine on or off and does not add up, that fast time gives the same result, that the setting is saved (old saves let the crew trim), and that T and the action wheel open the trim panel with "Well trimmed", "Too tight" and "Too loose" feedback.
- **Works with:** `SailTrim`, `GameSession`, `Simulation`, `SessionState`, `SailTrimPanel`, `SailingPanel`, the app scene.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests.
- **If you change it:** Only the safety net changes; if it fails, sail trim may make the boat too fast or slow, or the panel may not open.

### `tests/suites/test_sailing.gd`

**Purpose:** Checks the automatic choice between sails and engine, and that voyages run the same however fast time goes.
- **What it does:** Checks that the boat sails in good wind and motors in light air, waits for a lasting change before switching, never flips back and forth, sets the spinnaker on a run, gives the same voyage at normal speed, sped-up time or sleeping, gives a good arrival estimate, still raises weather warnings, and saves and loads the sail/engine state (including old saves from Iteration 002).
- **Works with:** `PropulsionController`, `PropulsionState`, `VesselProfile`, `WindField`, `Simulation`, `GameSession`, `SessionState`, `SaveManager`, `WeatherFixtures`.
- **Keeps:** Nothing of its own; it writes a temporary old-style save file in slot 3 and removes it.
- **When it runs:** Only in tests.
- **If you change it:** Only the safety net changes; if it fails, sailing speeds, arrival times or saves may be affected.

### `tests/suites/test_sailing_correctness.gd`

**Purpose:** Checks that the deck turns with the boat and that saving at sea puts everything back exactly.
- **What it does:** Checks that the deck is drawn along the boat's heading and turns when the autopilot turns (wherever the captain stands, and after visiting the cabin). It saves and loads at sea in many situations (helm, bow, stern, cabin, at anchor, in a gale at night) and checks that the captain, time, position, weather and money come back exactly, and that reloading gives the same weather. It also checks quicksave (F5) and quickload (F9).
- **Works with:** the app scene, `BoatArea`, `GameSession`, `Simulation`, `SaveManager`, `SettingsManager`, `WindField`, `WeatherFixtures`.
- **Keeps:** Nothing of its own; it clears save slots 1–3 and the quicksave before and after.
- **When it runs:** Only in tests.
- **If you change it:** Only the safety net changes; if it fails, saves at sea may not restore properly or the deck may face the wrong way.

### `tests/suites/test_sailing_presentation.gd`

**Purpose:** Checks how sailing and motoring look and sound in the real game.
- **What it does:** Sets known sailing states and checks that the sails lie on the side away from the wind, the spinnaker flies on a run and comes down when the wind moves forward, the sails are furled while motoring, the engine sound is loud on deck and muffled in the cabin and stops when sailing, on arrival and in the main menu, the HUD shows mode, wind and arrival estimate, and the chart's wind overlay and its toggle work.
- **Works with:** the app scene, `SailRig`, `AudioManager`, `GameSession`, `PropulsionController`, `WorldMap`, `WindField`.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests (it saves screenshots when asked).
- **If you change it:** Only the safety net changes; if it fails, sails, engine sound, HUD or the wind overlay may look or sound wrong.

### `tests/suites/test_save_manager.gd`

**Purpose:** Checks that save slots are written, read and protected correctly.
- **What it does:** Checks empty and out-of-range slots, that saving writes a file with the right details (area, harbour, destination, time, format version), that loading gives back exactly what was saved, that "Continue" picks the newest good save, that a backup is kept when you overwrite, and that broken, unreadable or future-version files are reported instead of crashing. It also checks that a failed save leaves the old save untouched.
- **Works with:** `SaveManager`, `SessionState`.
- **Keeps:** Nothing of its own; it works in a separate test save folder and deletes slots 1–3 afterwards.
- **When it runs:** Only in tests.
- **If you change it:** Only the safety net changes; if it fails, players' saves could be lost or misread.

### `tests/suites/test_secret_achievements.gd`

**Purpose:** Checks the seven secret captain's hat achievements.
- **What it does:** Checks that the secret achievements exist in the objectives data with small rewards, that each one is found in the right situation (first hat lost, third hat lost, €100 spent on hats, a new hat lost within five minutes, keeping your hat in dangerous weather, ten voyages with the original hat, losing it far out at sea), that each pays renown only once, even after loading, and that losing hats is never a way to earn money. Then it checks that the Captain's Log hides secret achievements until they are found.
- **Works with:** `ObjectiveCatalog`, `GameSession`, `Simulation`, `HatState`, `HatConfig`, `HatStory`, `CaptainsLogMenu`, the app scene.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests.
- **If you change it:** Only the safety net changes; if it fails, secret achievements could be revealed early, paid twice or not found at all.

### `tests/suites/test_settings_and_audio.gd`

**Purpose:** Checks the settings (volumes, window, VSync, UI size) and the sound system.
- **What it does:** Checks default settings, that volume sliders reach the sound channels at once (0 % mutes, over 100 % is capped), that settings survive a restart, that bad values in the settings file fall back safely, and, with a real window, that window modes and VSync are applied. It also checks that the sound manager reuses a fixed set of players and can start, swap and stop ambience and music. Since I022 it checks the wind volume: default 100 %, applied at once, kept after a restart.
- **Works with:** `SettingsManager`, `AudioManager`, Godot's `AudioServer` and `DisplayServer`.
- **Keeps:** Nothing of its own; it uses a separate test settings file and deletes it.
- **When it runs:** Only in tests (window checks are skipped without a real window).
- **If you change it:** Only the safety net changes; if it fails, settings or sound may not work as expected.

### `tests/suites/test_simulation.gd`

**Purpose:** Checks the game clock, voyages, sleeping, weather warnings and changing course.
- **What it does:** Checks that the game starts on 1 May 2026 at 08:00, that time speeds up correctly and stops while paused, that voyages move at the right speed whatever the time step, that arrival is reported once and exactly on time, and that sleeping is interrupted by arrival or a weather warning. It uses a fixed strong-wind area to check that warnings come about 6 hours ahead and only once, and that you can change course or destination at sea without the boat jumping.
- **Works with:** `Simulation`, `GameSession`, `WeatherFixtures`, `WeatherModel`, `SeaRouter`, `PortCatalog`, `GeoMath`.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests.
- **If you change it:** Only the safety net changes; if it fails, time, voyages or weather warnings may behave wrongly.

### `tests/suites/test_solar_panels.gd`

**Purpose:** Checks the decorative solar panels on all four boats.
- **What it does:** Checks that every boat has solar panels sized for it (one on the smallest, three on the largest), that they sit at the stern out of the captain's and Snøvs's way, have no collision, turn with the boat, show in harbour, underway, at anchor and in the boatyard preview, and are only for looks (nothing in the save, nothing to buy, no per-frame work).
- **Works with:** the app scene, `BoatArea`, `VesselVisual`, `SolarPanels`, `TestWalkability`, `DeckCompanionSpots`, `BoatCare`, `BoatyardMenu`, `GameSession`.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests (it saves screenshots when asked).
- **If you change it:** Only the safety net changes; if it fails, the panels may be in the way, missing or affect the save.

### `tests/suites/test_soundtrack.gd`

**Purpose:** Checks the game's original music and how it changes with the situation.
- **What it does:** Checks that the three music pieces load, loop and are long, and that they really sound. It checks that the music picks the right piece (night music at night; by day, sailing music on deck at sea and the home tune in harbour, in the cabin and in menus), that changes fade smoothly and wait a moment, that a piece resumes at the start of a phrase, that opening the chart, pause menu or settings does not restart it, that fast time does not flip it back and forth, and that muting music leaves sound effects alone.
- **Works with:** `MusicDirector`, `AudioManager`, `SettingsManager`, `GameSession`, `Simulation`, the app scene.
- **Keeps:** Nothing of its own; it shortens the music timings for the test and restores them.
- **When it runs:** Only in tests.
- **If you change it:** Only the safety net changes; if it fails, music may cut, restart or play in the wrong place.

### `tests/suites/test_sprite_workshop.gd`

**Purpose:** Checks the Sprite Workshop, the system that lets new artwork replace the game's built-in pictures.
- **What it does:** Checks that the art lists (manifests) are tidy and honest and that no replacement pictures are left in the project, that missing pictures fall back to the original, are loaded only once, and that wrong-sized or unreadable files are refused with a clear warning. It temporarily installs test pictures for every ready entry and for three examples in the running game (the anchor buoy, Snøvs resting, and the Arctic Wanderer 26 coachroof) and checks they appear at the right size and place, then removes them again.
- **Works with:** `ArtworkResolver`, `TestArtFixtures`, `TestWalkability`, `CompanionVisualSet`, `AnchorSignals`, `VesselVisual`, `SolarPanels`, `FishArt`, `HatArt`, `ShipCompanion`, the app scene.
- **Keeps:** Nothing of its own; every test picture it installs is removed again.
- **When it runs:** Only in tests (it saves screenshots when asked).
- **If you change it:** Only the safety net changes; if it fails, replacement art may not show, or bad art files could break the look.

### `tests/suites/test_steady_hands.gd`

**Purpose:** Checks that the interface stays put, on screen, closable and translated (Steady Hands).
- **What it does:** Shows, updates and hides weather warnings many times (English and Danish, day and night, Trip Details collapsed and expanded) and checks that Trip Details never moves and the warning never covers it. It then opens every window the game offers, from the game's own entry points, at several screen shapes and interface sizes in both languages. Each window must stay inside the screen, close with Esc and show no raw placeholders or English text in Danish. The test also checks the HUD's panels against each other, the main screens, the longest harbour name with long notices, what happens when the situation changes under an open window, and that nothing invisible catches the mouse. It also checks dusk and dawn: over a whole day the interface is either day or night (never parked half-way) and changes twice, and text stays readable on its panels all through the change.
- **Works with:** `App`, `Hud`, every window class, `SettingsManager`.
- **Keeps:** Nothing (the window size and settings are restored).
- **When it runs:** With the other suites (`test_runner.tscn`).
- **If you change it:** Only the tests change; a new window belongs in its list of openers.

### `tests/suites/test_turbocharge.gd`

**Purpose:** Checks that the faster weather shortcuts give exactly the same results as the full calculation.
- **What it does:** Compares the quick weather check with the full one at many places, dates and seeds around the world, compares route weather hazards and weather damage with the previous way of calculating them (kept inside the test), checks that the new way is cheaper, and checks that three nights of sleeping at sea end the same way twice.
- **Works with:** `WeatherModel`, `Simulation`, `WeatherDamage`, `SeaRouter`, `GameSession`, `WindField`, `GeoMath`.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests.
- **If you change it:** Only the safety net changes; if it fails, weather warnings or storm damage may have changed without anyone meaning to.

### `tests/suites/test_upkeep.gd`

**Purpose:** Checks the cost of sailing: boat condition, storm damage, repairs, rescue, money and provisions.
- **What it does:** Checks the starting state (€10,000, 14 days of food and water, boats at 100 %), that provisions are used up at the right rate and warn when low, that storms (not ordinary wind) damage the boat according to how tough it is, that results are the same at any time speed, that repairs cost money in harbour, that a boat at zero condition is rescued to Copenhagen for a €1,000 fee (never below €0), and that all this is saved and old saves load.
- **Works with:** `GameSession`, `Simulation`, `WeatherDamage`, `WeatherFixtures`, `Provisions`, `VesselCondition`, `BoatCare`, `SaveManager`, `VesselCatalog`.
- **Keeps:** Nothing of its own; it uses save slots 2 and 3 briefly and deletes them.
- **When it runs:** Only in tests.
- **If you change it:** Only the safety net changes; if it fails, damage, rescue fees, provisions or saves may be wrong.

### `tests/suites/test_upkeep_ui.gd`

**Purpose:** Checks the screens for boat condition, provisions, the boatyard and rescue in the real game.
- **What it does:** Checks that the HUD (the on-screen info bar) shows hull condition, money, food and water; that the provisions station in every cabin opens the provisions panel and leads to the grocery store; that the food and water crates empty as time passes; that damage marks grow as the boat wears and vanish after repair; that the boatyard panel keeps its size and offers repair and restocking; and that the rescue report appears and pauses the game. It also checks the developer test panel (F10) and that players never see it, and that the ship's cat never blocks a station.
- **Works with:** the app scene, `ProvisionsMenu`, `GroceryMenu`, `ProvisionDisplay`, `BoatyardMenu`, `BoatCareMenu`, `RescueDialog`, `DevTools`, `DevTestPanel`, `ShipCompanion`, `InteractionSensor`, `TestWalkability`, `GameSession`.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests (it saves screenshots when asked).
- **If you change it:** Only the safety net changes; if it fails, the upkeep screens, the developer tools or the cat's placement may misbehave.

### `tests/suites/test_vessels.gd`

**Purpose:** Checks the four boats, the boatyard and life aboard each boat.
- **What it does:** Checks the boat list (Arctic Wanderer 26 as the starter, Wing 33, Clam 40, Frogleap 36), that each boat's deck and cabin have every picture slot, station and starting spot, that every station can be walked to, and that each boat sails at its own speeds. It uses the boatyard to change boats (only in harbour), walks through life aboard each boat (cabin, companion, chart, sleep, sails, spinnaker, engine), checks that swapping in sprite pictures never changes collisions, and checks saving, loading and old saves.
- **Works with:** `VesselCatalog`, `VesselVisual`, `VesselVisualProfile`, `BoatArea`, `BoatyardMenu`, `SailRig`, `ShipCompanion`, `TestWalkability`, `GameSession`, `Simulation`, `SaveManager`, the app scene.
- **Keeps:** Nothing of its own; it uses save slots 2 and 3 briefly and deletes them.
- **When it runs:** Only in tests (it saves screenshots when asked).
- **If you change it:** Only the safety net changes; if it fails, a boat may be missing parts, have unreachable stations, sail at wrong speeds or load wrongly.

### `tests/suites/test_visual_prototype.gd`

**Purpose:** Checks the painted ("Illustrated") look of the boats and the harbour.
- **What it does:** Checks that the owner's cat drawings are untouched, that the Wing 33, Clam 40 and Frogleap 36 have painted picture sets that can be replaced, and that switching between Illustrated and Classic art changes only the look, never where you can walk or what you can use. It checks the painted harbour (Copenhagen with its Nyhavn landmark, a plain harbour elsewhere, signs only for real services, no harbour at sea), that the grocery store and boatyard still open, and the Artwork choice in Settings. Since I021 Kiel shows the gabled harbour town look instead of a bare quay.
- **Works with:** `VesselCatalog`, `VesselVisual`, `SettingsManager`, `HatArt`, `HarbourArt`, `HarbourLandmark`, `HarbourFacilities`, `BoatArea`, `SettingsMenu`, `TestWalkability`, the app scene.
- **Keeps:** Nothing of its own; it leaves the art style set to Illustrated.
- **When it runs:** Only in tests (it saves screenshots when asked).
- **If you change it:** Only the safety net changes; if it fails, the painted art may hide gameplay changes, the harbour may show wrong signs, or the art setting may not stick.

### `tests/suites/test_voyage_persistence.gd`

**Purpose:** Checks saving and loading in the middle of a voyage, and very old saves.
- **What it does:** Saves while sailing to Kiel and checks that loading brings back the clock, time speed, position, route, captain's spot and already-given weather warnings (which are not repeated), and that the voyage then reaches Kiel. It loads a save from Iteration 001 and checks it is updated sensibly, and checks that broken voyage saves are refused without touching the game in progress.
- **Works with:** `SaveManager`, `GameSession`, `Simulation`, `WeatherFixtures`, `SettingsManager`, `SeaRouter`, `PortCatalog`.
- **Keeps:** Nothing of its own; it deletes save slots 1–3 when done.
- **When it runs:** Only in tests.
- **If you change it:** Only the safety net changes; if it fails, saves made at sea or old saves may not load properly.

### `tests/suites/test_weather.gd`

**Purpose:** Checks the weather system: wind, gale areas, thunderstorms and tropical cyclones.
- **What it does:** Checks that the weather is the same for the same place, time and seed (a starting value for randomness), that gale areas form, move, grow and fade with irregular outlines, that thunderstorms are mostly a summer thing with gusty episodes, and that cyclones keep to their own oceans and seasons (never in European waters). With test weather it checks wind directions, how wind fades from the core, all four boats sailing through a gale, warnings that are not repeated, identical results at any time speed, pause, and saving and old saves.
- **Works with:** `WeatherModel`, `WeatherEvent`, `WeatherFixtures`, `WindField`, `Simulation`, `GameSession`, `SaveManager`, `VesselCatalog`, `GeoMath`.
- **Keeps:** Nothing of its own; it uses save slots 2 and 3 briefly and deletes them.
- **When it runs:** Only in tests.
- **If you change it:** Only the safety net changes; if it fails, weather may become unpredictable, appear in the wrong places, or warnings may repeat.

### `tests/suites/test_weather_ui.gd`

**Purpose:** Checks how the player sees and hears the weather in the real game.
- **What it does:** With test weather near Copenhagen, checks that the chart draws exactly the active weather areas with their real irregular outlines and labels, that they stay put while panning, stand still when paused and move with time, that the Weather tab lists hazards on the course and its legend explains all four kinds, that the HUD shows a gale with gusts and the storm sound plays and stops, and that a storm forming on the course wakes a sleeping captain once, with the reason shown.
- **Works with:** the app scene, `WorldMap`, `MapView`, `WeatherLegend`, `WeatherStyle`, `WeatherFixtures`, `WeatherModel`, `GameSession`, `Simulation`.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests (it saves screenshots when asked).
- **If you change it:** Only the safety net changes; if it fails, weather on the chart, the HUD, storm sounds or sleep warnings may be wrong.

### `tests/suites/test_well_run_ship.gd`

**Purpose:** Checks performance safeguards and the "time passing" screens (sleep, dawn and dusk cards, Long Passage).
- **What it does:** Checks that day/night recolouring of the interface is a single cheap change, and that repeated trips between deck, cabin, chart and sleep do not make the game grow. It checks dates and weekdays, that sleeping shows a ticking clock past midnight and returns control (a key skips it), that a dawn or dusk card appears once per twilight (not after a load or over a menu), and that the Long Passage voyage map follows the real route, through the Kiel Canal and across the Date Line, stops for events with "Sail on", and stops at a planned anchorage.
- **Works with:** the app scene, `TimePassage`, `DayNightWatch`, `Daylight`, `UiTheme`, `VoyageMap`, `Simulation`, `GameSession`, `SeaRouter`, `WorldMap`.
- **Keeps:** Nothing of its own; it switches the time-passage screens on for the test and off again.
- **When it runs:** Only in tests (it saves screenshots when asked).
- **If you change it:** Only the safety net changes; if it fails, the game may slow down over time, or sleep, twilight cards or Long Passage may misbehave.

### `tests/suites/test_wind.gd`

**Purpose:** Checks the background wind and how fast a boat sails in it.
- **What it does:** Checks wind direction conventions (a westerly comes from 270° and blows east; port and starboard), that the wind is the same for the same place, time and seed, stays between 0 and 45 kn, changes smoothly in space and time, and matches real climate (Atlantic westerlies, Portuguese trades, the Meltemi, the Mistral, a changeable Baltic). It also checks that wind look-ups are fast, and the sailing speed rules: no speed head to wind, a top speed of about 10 kn, more wind never slower, and a small spinnaker bonus only downwind.
- **Works with:** `WindField`, `PropulsionState`, `VesselProfile`, `SessionState`.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests.
- **If you change it:** Only the safety net changes; if it fails, the wind may feel unrealistic or boats may sail at odd speeds.

### `tests/suites/test_wind_overlay.gd`

**Purpose:** Checks the wind arrows on the chart and the wind time controls.
- **What it does:** Checks that the chart's quick wind look-up gives exactly the same wind as the full weather, that arrows are only drawn at sea, that a still chart does no extra work and small pans reuse what was already worked out, and that the old arrows stay until the new ones are ready. It checks that zoomed far out the chart says "Zoom in to see wind details.", that the time buttons step one hour up to ±6 hours with NOW, FORECAST and PAST labels without changing the game, that a fast clock does not redraw constantly, and that closing the chart stops the wind work.
- **Works with:** `WeatherModel`, `WindLayer`, `MapView`, `WorldMap`, `SeaRouter`, `NavGrid`, `GameSession`, `Simulation`, the app scene.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests (it saves screenshots when asked).
- **If you change it:** Only the safety net changes; if it fails, the chart's wind arrows may be wrong, slow, or appear on land.

### `tests/suites/test_wider_world.gd`

**Purpose:** Checks I021, A Wider, Warmer World: the new harbours, harbour looks, special harbours, arrival card, new fish and cabin things.
- **What it does:** Checks that the 16 new harbours exist with a sentence, a source and a grocery store, in English and Danish. Every harbour has a look with a finished picture, chosen by what the place looks like (New Zealand like Norway, Willemstad like Denmark). The special harbours are exactly those with their own picture, and a missing picture shows the plain quay. The new fish live where they really live, have art, fair prices and Danish names, and a record survives a save. The three new cabin things are on sale. Old saves load, mooring again and again adds nothing, both sides of the date line work, and the arrival card shows picture and words without blocking.
- **Works with:** `PortCatalog`, `HarbourLooks`, `HarbourArt`, `HarbourDressing`, `WorldMap`, `FishingCatalog`, `FishArt`, `HarbourTrades`, `SessionState`, `SeaRouter`, `SettingsManager`, the app scene.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests.
- **If you change it:** Only the checks change. A failure points at harbour data, pictures, the look table, fish data or the arrival card.

### `tests/suites/test_world_chart_render.gd`

**Purpose:** Checks that the world chart never shows empty gaps where land should be.
- **What it does:** Pans the chart all the way round the globe several times, both ways, zoomed out and zoomed in, and checks that known land (Australia, New Zealand, Japan, Alaska, Argentina, New Guinea, China, Brazil) is drawn wherever it appears on screen. It also checks that screen and map positions match across the Date Line and that harbours can still be picked after a lot of panning.
- **Works with:** the app scene, `WorldMap`, `MapView`, `GeoMath`.
- **Keeps:** Nothing of its own.
- **When it runs:** Only in tests (it saves a screenshot when asked).
- **If you change it:** Only the safety net changes; if it fails, land may vanish from parts of the world chart or harbours may be hard to click.

### `tests/suites/test_world_voyage.gd`

**Purpose:** The big "Copenhagen to Paradise" journey test: sails the smallest boat all the way to Tahiti.
- **What it does:** Sails the Arctic Wanderer 26 from Copenhagen via Las Palmas, the Caribbean and the Panama Canal across the Pacific to Papeete, in Long Passage time on the real seeded weather. On the way it stocks up, checks passage readiness, fishes and cooks once a day, saves and reloads in mid-Atlantic, goes ashore in harbours, and checks that every leg arrives, stores last, no rescue is needed and the boat never jumps across the map.
- **Works with:** the app scene, `GameSession`, `Simulation`, `PassageReadiness`, `Provisions`, `SeaRouter`, `SaveManager`, `WeatherModel`, `WindField`, `PortCatalog`.
- **Keeps:** Nothing of its own; it uses save slot 3 briefly and deletes it.
- **When it runs:** Only in tests (it is one of the longest runs).
- **If you change it:** Only the safety net changes; if it fails, a long ocean voyage may no longer be possible, or stores, fishing or saving at sea may be broken.

## Test runner, probes and tools

### `tests/benchmark.gd`

**Purpose:** A stopwatch for the whole game: it times loading, route planning, the chart, a ten-day voyage and saving.
- **What it does:** Plans a set of European and worldwide routes, starts the game, opens and closes the chart, sails ten simulated days towards Piraeus and saves and loads once. It prints one `BENCH {...}` line and can write the numbers to a file.
- **Works with:** `SeaRouter`, `PortCatalog`, `GameSession`, `Simulation`, `SaveManager`, the chart's `MapView`.
- **Keeps:** Nothing of its own; just the measured numbers while it runs.
- **When it runs:** Only by hand: `godot --headless --path . res://tests/benchmark.tscn -- --out=/tmp/bench.json` (leave out `--headless` for frame times).
- **If you change it:** Nothing in the game changes; only comparisons with older benchmark results stop matching.

### `tests/benchmark_105b.gd`

**Purpose:** Measures how smoothly the night scenes, the fishing reel and the chart overlays run (Revision 0.105b).
- **What it does:** Shows the cabin and deck at midnight (moored, under way, at anchor), a fish on the line, steps through the wind time navigator and fills the anchorage overlay, timing every frame. It prints `BENCH105B {...}` and records the version, commit and a before/after label.
- **Works with:** The game scene (`app.tscn`), `GameSession`, `Simulation`, `WindField`, the chart's wind and anchorage layers.
- **Keeps:** Nothing of its own; just the results while it runs.
- **When it runs:** Only by hand, with a screen: `xvfb-run godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/benchmark_105b.tscn -- --out=/tmp/b.json --label=after`.
- **If you change it:** Nothing in the game changes; old and new results may no longer compare.

### `tests/benchmark_17.gd`

**Purpose:** Measures the cost of the chart's wind overlay and the weather behind it (Iteration 17).
- **What it does:** Opens the chart again and again, times frames at four zoom levels with wind on and off (still, panning, zooming), times wind redraws, a day of sailing and a day of Long Passage, and saving. It prints `BENCH17 {...}`.
- **Works with:** `MapView`, `WorldMap`, `WeatherModel`, `Simulation`, `GameSession`, `SaveManager`.
- **Keeps:** Nothing of its own.
- **When it runs:** Only by hand: `godot --headless --path . res://tests/benchmark_17.tscn -- --out=/tmp/b.json` (without `--headless` for real frame times).
- **If you change it:** Nothing in the game changes.

### `tests/benchmark_18.gd`

**Purpose:** Measures frame times of the scenes changed in Iteration 18 (night lighting, fishing reel, wind time navigator).
- **What it does:** Same scenes as the 0.105b benchmark, but without the anchorage overlay or the commit/label record. Prints `BENCH18 {...}`.
- **Works with:** The game scene, `GameSession`, `Simulation`, `WindField`, the chart's wind layer.
- **Keeps:** Nothing of its own.
- **When it runs:** Only by hand, with a screen: `xvfb-run godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/benchmark_18.tscn -- --out=/tmp/b18.json`.
- **If you change it:** Nothing in the game changes.

### `tests/benchmark_wrs.gd`

**Purpose:** A long "is the ship running well?" probe: stutters and slow growth during sleep, sunrise/sunset, the chart, Long Passage and long sessions.
- **What it does:** Walks the captain around, runs day/night changes at 20x speed, sleeps across midnight, sails, runs Long Passage and repeats 20 rounds of everyday actions, timing frames and counting "stalls" (frames over 50 ms). After each step it also counts nodes, signals, sounds and caches, so leaks show up as a trend. Extra modes: `--presented` and `--turbo`.
- **Works with:** The game scene, `GameSession`, `Simulation`, `Daylight`, `UiTheme`, `WeatherModel`, `SeaRouter`, `SessionLog`, `SaveManager`.
- **Keeps:** Nothing of its own.
- **When it runs:** Only by hand, with a screen: `xvfb-run godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/benchmark_wrs.tscn -- --out=/tmp/w.json --label=before`.
- **If you change it:** Nothing in the game changes; before/after comparisons depend on it staying the same.

### `tests/cabin_light_18.gd`

**Purpose:** Measures how bright the night cabin is on all four boats, for comparing lighting before and after a change.
- **What it does:** For each boat, at Copenhagen at local midnight, it photographs the cabin without the on-screen panels and prints the brightness at the lamps, in the floor corners, across the floor and on the captain.
- **Works with:** The game scene, `GameSession`, `BoatLighting`, `BoatArea`.
- **Keeps:** Nothing of its own; saves PNG pictures to the chosen folder.
- **When it runs:** Only by hand, with a screen: `xvfb-run godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/cabin_light_18.tscn -- --out=DIR --label=before`.
- **If you change it:** Nothing in the game changes.

### `tests/helpers/art_fixtures.gd`

**Purpose:** Makes loud pink-and-yellow test pictures to stand in for real artwork during Sprite Workshop tests.
- **What it does:** Draws a checkered replacement picture at the size the art list expects, can write a deliberately broken file, tells whether a texture is the test picture, removes it again, and lists any replacement PNGs left behind.
- **Works with:** `ArtworkResolver` (the artwork list and folder); used by `test_sprite_workshop`, `restart_105b` and `screenshots_105b`.
- **Keeps:** Nothing of its own; files it writes are meant to be removed by the test.
- **When it runs:** Only in tests.
- **If you change it:** Sprite Workshop tests may fail, or test pictures might be left in the art folder.

### `tests/helpers/reel.gd`

**Purpose:** Lets a test reel in a fish through the real reel dial, like a player with perfect timing.
- **What it does:** Steps the needle round, puts it in the middle (or at the edge) of the target arc, and presses, until the reeling ends. Says whether the catch was landed.
- **Works with:** `FishingMenu`, `ReelTiming`; used by the fishing suites, `restart_18` and `screenshots_18`.
- **Keeps:** Nothing.
- **When it runs:** Only in tests.
- **If you change it:** Fishing tests may start failing to land fish.

### `tests/helpers/walkability.gd`

**Purpose:** Finds where the captain can really walk on a deck or in a cabin, and from where each station can be used.
- **What it does:** Spreads out from a starting point on a grid, testing the captain's real body size against the real walls, then measures how close each spot is to stations and fixtures.
- **Works with:** `BoatArea`, `Interactable`, `BoatFixture`; used by `test_vessels`, `test_visual_prototype`, `test_solar_panels`.
- **Keeps:** Nothing.
- **When it runs:** Only in tests.
- **If you change it:** Boat layout tests could pass or fail wrongly (e.g. say a station can't be reached).

### `tests/pacing_18.gd`

**Purpose:** Counts how often Long Passage stops on an ocean crossing, with and without fishing.
- **What it does:** Sails Copenhagen to Las Palmas for up to 12 game days three times (no fishing; trolling and stopping for every bite; stopping only for fish worth keeping) and prints a `PACE` line with the stop reasons.
- **Works with:** `GameSession`, `Simulation`, `FishingState`, `WindField`.
- **Keeps:** Nothing.
- **When it runs:** Only by hand: `godot --headless --path . res://tests/pacing_18.tscn`.
- **If you change it:** Nothing in the game changes.

### `tests/restart_105b.gd`

**Purpose:** Checks that anchoring and replaced artwork survive closing and reopening the game (Revision 0.105b).
- **What it does:** In separate runs it saves a boat at anchor off Antigua and one on the Magic Anchor offshore, then reloads and checks everything plays on exactly the same; it also installs a test picture for the cat, checks a new run uses it, removes it and checks the original is back.
- **Works with:** The game scene, `GameSession`, `SaveManager`, `MagicAnchorDeployment`, `ArtworkResolver`, `TestArtFixtures`.
- **Keeps:** Its own test save folder and an expectations file, removed at the end.
- **When it runs:** Only by hand, as separate runs: `godot --headless --path . res://tests/restart_105b.tscn -- --phase=write`, then `--phase=read`; for art: `--phase=art_install`, `godot --headless --path . --import`, `--phase=art_read`, `--phase=art_after`.
- **If you change it:** Nothing in the game changes.

### `tests/restart_17.gd`

**Purpose:** Checks that saving while sailing and loading in a fresh game puts everything back exactly (Iteration 17).
- **What it does:** Saves three times under way (on deck near the bow, in the cabin, in poor weather), sails six more hours each time, then in a second run loads each save and checks the captain's spot, the boat, the time, route, weather, and that the next six hours go the same way.
- **Works with:** The game scene, `GameSession`, `Simulation`, `SaveManager`.
- **Keeps:** Its own test save folder and an expectations file.
- **When it runs:** Only by hand, twice: `godot --headless --path . res://tests/restart_17.tscn -- --phase=write`, then `-- --phase=read`.
- **If you change it:** Nothing in the game changes.

### `tests/restart_18.gd`

**Purpose:** Checks that fishing, anchorages and sail trim survive a save and a fresh start (Iteration 18).
- **What it does:** Saves three situations: a cool box with kept and released fish, a boat anchored at a chart anchorage with the companion on deck, and a hand-trimmed boat under way. A second run loads them and checks every detail and that the voyages continue exactly as before.
- **Works with:** The game scene, `GameSession`, `Simulation`, `SaveManager`, `FishingCatalog`, `WorldMap`, the `reel.gd` helper.
- **Keeps:** Its own test save folder and an expectations file.
- **When it runs:** Only by hand, twice: `godot --headless --path . res://tests/restart_18.tscn -- --phase=write`, then `-- --phase=read`.
- **If you change it:** Nothing in the game changes.

### `tests/restart_check.gd`

**Purpose:** The original "close and reopen" check: settings and a rich save must come back after a restart.
- **What it does:** First run: changes settings, sails to Gothenburg, loses and replaces the captain's hat, publishes a travel update, switches to the trimaran, starts for Kiel and saves. Second run: checks settings, position, voyage, Captain's Log, renown, hat, weather, money, stores, boat condition and the diagnostic log.
- **Works with:** `SettingsManager`, `SaveManager`, `GameSession`, `Simulation`, `WeatherModel`, `SessionLog`.
- **Keeps:** Its own settings file, save folder, log folder and expectations file, all cleaned up after the read.
- **When it runs:** Only by hand, twice: `godot --headless --path . res://tests/restart_check.tscn -- --phase=write`, then `-- --phase=read`.
- **If you change it:** Nothing in the game changes.

### `tests/screenshots_105b.gd`

**Purpose:** Takes the picture evidence for Revision 0.105b: anchorages abroad, night at anchor and replaced-artwork fallback.
- **What it does:** Anchors off Antigua and (with the Magic Anchor) off Madeira, shows night at anchor, then installs, removes and wrongly sizes a replacement buoy picture, checking and photographing each case.
- **Works with:** The game scene, `GameSession`, `AnchorSite`, `ArtworkResolver`, `TestArtFixtures`.
- **Keeps:** Nothing; writes PNGs to the folder given.
- **When it runs:** Only by hand, with a screen: `xvfb-run godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/screenshots_105b.tscn -- --out=DIR`.
- **If you change it:** Nothing in the game changes.

### `tests/screenshots_16.gd`

**Purpose:** Takes the twenty review pictures of "The World Awaits" (Iteration 16): the world chart, long routes and ocean passages.
- **What it does:** Photographs the chart at many places and zooms, several long routes, the Long Passage panel, an arrival in Papeete and going ashore, and joins three zoom pictures into one.
- **Works with:** The game scene, `WorldMap`, `MapView`, `GameSession`, `Simulation`.
- **Keeps:** Nothing; writes into `docs/screenshots/iteration16/` in the project.
- **When it runs:** Only by hand, with a screen: `godot --path . --resolution 1600x900 res://tests/screenshots_16.tscn`.
- **If you change it:** Nothing in the game; only the documentation pictures.

### `tests/screenshots_17.gd`

**Purpose:** Takes the thirty review pictures of "Let There Be Light" (Iteration 17): light through the day, weather, the Dreamer's Map.
- **What it does:** Photographs cabins and decks at noon, dusk and night, the Dreamer's Map, the chart, sailing views, rain and lightning, and docking. `--only=` picks a subset.
- **Works with:** The game scene, `GameSession`, `Simulation`, `Daylight`, `WeatherFixtures`, `ChartPlotter`, `CaptainsLogMenu`.
- **Keeps:** Nothing; writes into `docs/screenshots/iteration17/`.
- **When it runs:** Only by hand, with a screen: `godot --path . --resolution 1600x900 res://tests/screenshots_17.tscn [-- --only=cabin]`.
- **If you change it:** Nothing in the game; only the documentation pictures.

### `tests/screenshots_18.gd`

**Purpose:** Takes the fishing pictures for Iteration 18: the reel dial, catches, fish art, trophies and dragging an anchorage on the chart.
- **What it does:** Shows bites and reeling (perfect and missed), kept and released catches, the cool box and preferences, each fish's artwork, an animation strip and a sheet of all species, then an anchorage waypoint being dragged.
- **Works with:** The game scene, `FishingMenu`, `FishingCatalog`, `FishPortrait`, `WorldMap`, the `reel.gd` helper.
- **Keeps:** Nothing; writes PNGs to the folder given.
- **When it runs:** Only by hand, with a screen: `xvfb-run godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/screenshots_18.tscn -- --out=DIR`.
- **If you change it:** Nothing in the game changes.

### `tests/screenshots_chartroom.gd`

**Purpose:** Photographs every main screen of the game by day and by night, to check the Chartroom look.
- **What it does:** At local noon and midnight it shows the main menu, deck, cabin, trophy board, boat care, shops, Captain's Log, sleep, galley, chart, sailing, fishing, Dreamer's Map, pause and settings, and saves a picture of each.
- **Works with:** The game scene, `SettingsManager`, `UiTheme`, `GameSession`, `FishingCatalog`.
- **Keeps:** Nothing; uses a test settings file and writes PNGs (default `docs/screenshots/chartroom_ui`).
- **When it runs:** Only by hand, with a screen: `xvfb-run godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/screenshots_chartroom.tscn -- --out=DIR [--only=day|night]`.
- **If you change it:** Nothing in the game changes.

### `tests/screenshots_i021.gd`

**Purpose:** Takes the pictures for the I021 report: every harbour look, the special harbours, the arrival card and the special star on the chart.
- **What it does:** Moors the boat in a harbour of each of the nine looks and in each special harbour and photographs the deck. It shows the arrival card (in English and in Danish), then opens the chart by day and by night with Valletta and Symi selected, and the Dreamer's Map.
- **Works with:** The app scene, `HarbourLooks`, `PortCatalog`, `GameSession`, `UiTheme`, `SettingsManager`, `WindField`.
- **Keeps:** Nothing; it writes PNG files.
- **When it runs:** Only by hand, with a real screen or Xvfb: `res://tests/screenshots_i021.tscn -- --out=DIR`.
- **If you change it:** Only the screenshots change.

### `tests/one_clock_sea_trial.gd`

**Purpose:** A five-minute "sea trial" that measures where the time goes when the clock runs faster than 1x, especially at dawn, dusk, at night and in harbour (Operation One Clock).
- **What it does:** Starts a game on scratch saves, sails and moors in fixed places, and runs each scenario (day and night at 1x and 20x, dusk with and without the date card, the chart at dusk, harbour at night with and without its lights, and a minute at 20x). Each frame it times the simulation, the interface recolouring, the boat's light and the dawn/dusk watch separately, and the rendering. At the end it shows a table, copies it to the clipboard and saves it as `one_clock_sea_trial.txt`.
- **Works with:** The game scene, `GameSession`, `Simulation`, `UiTheme`, `DayNightWatch`, `BoatLighting`, `TimePassage`, `Daylight`.
- **Keeps:** Nothing of its own; the player's saves and settings are never used.
- **When it runs:** Only when started on purpose: in Godot open `tests/one_clock_sea_trial.tscn` and press F6, or (developers) `xvfb-run godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/one_clock_sea_trial.tscn -- --all --out=/tmp/one_clock.json`.
- **If you change it:** Nothing in the game changes; comparisons with earlier trials depend on the scenarios staying the same.

### `tests/test_runner.gd`

**Purpose:** The game's automatic test runner: it runs all 74 test suites and says how many checks passed.
- **What it does:** Moves saves, settings and logs to scratch test files, turns off the sleep/dawn animations, sets English and calm wind, and runs each suite in turn. It also gives the suites shared tools: checks, waiting, pressing keys, clicking, boarding a boat, setting the wind, planning routes and screenshots. Since I021 it also runs the wider-world suite. Since I022 it runs the I022 suite and lets the suites sail every boat without buying it. I022: it turns the Academy's offer and tips off for the other suites. It also runs the cabin windows suite. It also runs the Steady Hands interface suite. It also runs the Golden Harbours suite.
- **Works with:** Every suite in `tests/suites/`, plus `SaveManager`, `SettingsManager`, `SessionLog`, `TimePassage`, `WindField`, `Simulation`, `GameSession`.
- **Keeps:** The pass/fail counts and the list of failures.
- **When it runs:** By hand or in automation: `godot --headless --path . res://tests/test_runner.tscn` (options after `--`: `--only=name`, `--skip=name`, `--screenshots=DIR`).
- **If you change it:** Every test could be affected; a new suite file only runs once it is added to the list here.

### `tools/art/capture_previews.gd`

**Purpose:** Photographs the art the game draws in code (cabin things, sails, chart markers), so the Illustrated Catalogue's contact sheets show exactly what the player sees.
- **What it does:** Shows each cabin thing on a cabin-floor colour; then starts a game in scratch saves and, for each of the four boats, photographs it moored in Copenhagen, its cabin with every cabin thing, and under sail; finally crops the chart's markers (harbour, selected harbour, destination with the brass star, the boat, a waypoint, the Dreamer's Map pins) by day and by night. Nothing is drawn by the tool itself.
- **Works with:** `App`, `GameSession`, `CabinDecor`, `HarbourTrades`, `WindField`, `Simulation`, `MapView`; `tools/art/build_contact_sheets.py` puts the pictures on the sheets.
- **Keeps:** Nothing; writes PNGs into `docs/art/previews/` (scratch saves and settings, never the player's).
- **When it runs:** Only by hand, with a display: `xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tools/art/capture_previews.tscn -- --out=docs/art/previews`.
- **If you change it:** Only the catalogue's preview pictures change, not the game.

### `tools/build_theme.gd`

**Purpose:** Builds the game's shared look (colours, fonts, buttons, panels) as a theme file.
- **What it does:** Creates the navy, teal, cream and brass theme in code, with the Barlow fonts and the hand-lettered display font, and saves it as `assets/ui/next_harbor_theme.tres`.
- **Works with:** The fonts in `assets/fonts/`; the result is the project's theme, used by every screen.
- **Keeps:** Nothing; writes the theme file.
- **When it runs:** Only by hand: `godot --headless --path . -s res://tools/build_theme.gd` (run `godot --headless --path . --import` first on a fresh checkout).
- **If you change it:** After re-running it, every menu, button and panel in the game looks different.

### `tools/export_branding.gd`

**Purpose:** Turns the game's logo and icon drawings (SVG) into PNG pictures in several sizes.
- **What it does:** Renders each branding SVG at the listed heights and saves them in `assets/branding/png/`. Since I022 the logo is also exported 240 pixels high, for Godot's boot splash.
- **Works with:** The SVGs in `assets/branding/`; the loading screen uses two of the PNGs.
- **Keeps:** Nothing; writes PNG files.
- **When it runs:** Only by hand: `godot --headless --path . -s res://tools/export_branding.gd`.
- **If you change it:** The exported logos change, including the logo on the loading screen.

### `tools/navigation/world_land_to_res.gd`

**Purpose:** Converts the world's land shapes into a fast-loading file so the chart opens quickly.
- **What it does:** Reads `data/navigation/world/land.json`, projects the coastlines and islets to chart space and saves them as `data/navigation/world/land.res`.
- **Works with:** `MapProjection`, `WorldLand`; `MapView` loads the result.
- **Keeps:** Nothing; writes the resource file.
- **When it runs:** Only by hand, after `build_world.py`: `godot --headless --path . --script tools/navigation/world_land_to_res.gd`.
- **If you change it:** The land drawn on the chart can change or fail to load.

### `tools/vessels/render_art_templates.gd`

**Purpose:** Makes painting templates for each boat, so artists know where walls, stations and spawn points are.
- **What it does:** For every boat's deck and cabin it saves a reference picture (current art with landmarks drawn over it) and a guide picture (landmarks only, transparent), into each boat's `templates` folder.
- **Works with:** `VesselCatalog`, `VesselVisual`, `BoatFixture`, `Interactable`.
- **Keeps:** Nothing; writes PNGs.
- **When it runs:** Only by hand, with a display: `godot --path . --rendering-driver opengl3 res://tools/vessels/render_art_templates.tscn`.
- **If you change it:** Only the artist templates change, not the game.

### `tools/weather/measure_wind_variation.gd`

**Purpose:** Measures how much the wind changes from one step of the chart's wind time navigator to the next.
- **What it does:** Samples the weather on grids in five sailing areas at many times and prints how much speed and direction change after 30 minutes to 6 hours, for real wind and for the forecast.
- **Works with:** `WeatherModel`.
- **Keeps:** Nothing; only prints.
- **When it runs:** Only by hand: `godot --headless --path . -s res://tools/weather/measure_wind_variation.gd`.
- **If you change it:** Nothing in the game changes.
