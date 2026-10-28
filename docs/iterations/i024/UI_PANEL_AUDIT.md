# I024: floating panels, a focused audit

The direction since I024: when an interaction naturally belongs to a physical
thing aboard, it happens at that thing - but never at the cost of
readability, speed or safety. This is the audit of the current windows and
HUD panels (the openers in `tests/suites/test_steady_hands.gd` plus the HUD),
with what I024 changed and a short list of recommendations for later.

## What each panel is

| Panel | Essential now? | Used while sailing? | Tied to a thing aboard? | Notes |
|---|---|---|---|---|
| HUD: status, clock and time buttons, wind | yes | yes | - | keep as overlay |
| Weather / anchor / traffic warnings | yes | yes | - | keep as overlay (never make the Captain walk below for a warning) |
| Trip Details, Sailing details, chart plotter, radar | yes | yes | instruments | keep as overlays; I023 fixes (no shifting, no overlap) kept |
| Sail trim, Anchor | yes | yes | winches, windlass | already opened at those fittings; keep the window |
| Action wheel | yes | yes | - | keep; I024 made it shorter (one *Laptop* item instead of *Write a postcard* + *Work on your little game*) |
| Chart (navigation table) | yes | yes | chart table | already diegetic in spirit (opened at the table) |
| Captain's Log | often | yes | - | keep as the quick overview; its Objectives tab now points to the laptop for the full collection, and filler goals are no longer listed |
| Remote work, Publish travel update | rarely | no | **laptop** | **moved onto the laptop screen (I024)** |
| Postcards, Scrapbook | rarely | no | **laptop** | **moved onto the laptop screen (I024)** |
| Your little game | rarely | no | **laptop** | **moved onto the laptop screen (I024)** |
| Achievements / renown collection | rarely | no | **laptop** | **new, on the laptop (I024)** |
| Provisions, Galley, Make it home, Trophies, Sleep, World map | sometimes | no | lockers, stove, berth, framed map | already opened at their things; candidates for in-world presentation later |
| Grocery, Fishmonger, Chandlery, Sailmaker, Boatyard, Boat care, Haul-out, Go ashore | sometimes | no | the shops on the pontoon | opened at their signs; fine as windows |
| Pause, Settings, Save, Load, Difficulty, Handbook | as needed | - | - | keep as conventional windows (accessibility, settings) |
| Confirm dialogs, VHF call | events | yes | radio | keep |

**Duplicates found:** the travel update was offered both in the Captain's Log
and at the work station (kept in both: the Log is the quick path, the laptop
the home); postcards and the little game had their own wheel items and
windows (now on the laptop only); the Log's Objectives tab and the new
collection overlap (the Log keeps goals in progress, the laptop the history).

## Changed in I024 (low risk)

- The cabin work station is now **the laptop on the table** (a drawn prop in
  every cabin); using it brings the laptop up close and everything runs on its
  screen: Home, Publications (postcards, scrapbook, travel update), the
  Achievements collection and the Voyage history, plus remote work and the
  little game. The existing dialogs are reused unchanged inside the screen.
- The cabin's action wheel has one *Laptop* item instead of two pastime items.
- The Captain's Log no longer lists goals retired from the collection and says
  where the achievements are.

## Recommendations (not done; for a later iteration)

1. **Provisions and galley at their lockers**: show stores as the locker's
   own contents (the provisions board already hints at it) instead of a list
   window. Low risk, moderate effort.
2. **Trophies on the trophy board**: browse catches by looking at the board
   up close, like the laptop. Low risk.
3. **Captain's Log as a book at the navigation table** while keeping L as
   the quick overlay. Medium effort.
4. **Boat care at the engine and rig** (status where the equipment is), with
   the boatyard window kept for buying work. Medium effort.
5. Keep warnings, instruments, Trip Details, settings, pause and
   accessibility as overlays: they must stay reachable at once, anywhere.
