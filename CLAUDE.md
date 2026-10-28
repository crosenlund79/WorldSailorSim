# Little Captain's Hat: start here

A cozy 2D sailing game in Godot 4.7 (GDScript only), English and Danish.
Art direction: **Illustrated sailing realism. Cozy at heart.** Cozy first, less is more.

Read before editing code: [CAPTAINS_ORDERS.md](CAPTAINS_ORDERS.md) (the standing
orders; they win over anything here), then
[docs/technical/ARCHITECTURE.md](docs/technical/ARCHITECTURE.md) and the script's
entry in [docs/technical/GDSCRIPT_ARCHITECTURE.md](docs/technical/GDSCRIPT_ARCHITECTURE.md).

1. **Repository.** `crosenlund79/WorldSailorSim` is canonical. The original
   `crosenlund79/LittleCaptainsHat` is read-only history; never edit it.
2. **Branch.** Ongoing development and integration: `claude/friendly-fermat-dey23f`.
   Small adjustments, hotfixes and documentation are committed there.
3. **Latest iteration: I024** (The Company We Keep, 0.110a). The next one,
   I025, starts only when commissioned. History: [docs/DEVELOPMENT_HISTORY.md](docs/DEVELOPMENT_HISTORY.md).
4. **Major iterations** develop on `iteration/iNNN`, created at a recorded,
   remotely verified starting SHA, and end with `release/iNNN` at the final
   tested SHA. Release and backup branches are never moved, rewritten or
   force-pushed. Verify every branch with `git ls-remote origin` before
   reporting it; a local-only tag is not a checkpoint. Details: *Major
   iteration branches* in the Captain's Orders.
5. **Saves.** `SaveManager.SAVE_VERSION` (12) changes only with the Captain's
   approval. Keep every save field and content id (boats, upgrades, money,
   companions and their names, discoveries, journals, difficulty); new fields
   get safe defaults. Run the save suites when state or persistence changes.
6. **Localization.** Every player-facing string goes through the existing
   gettext setup (`locale/`, `docs/technical/LOCALIZATION.md`): after text
   changes run `python3 tools/i18n/extract.py` and `python3 tools/i18n/check.py`,
   add Danish, and check the layout fits in both languages.
7. **Artwork.** Gameplay never depends on art. The Captain's replacements win
   (`art_replacements/`, ArtworkResolver; `DEV_GUIDES/SPRITES.md`); generated
   art in `assets/` keeps stable paths, ids and canvases and is regenerated only
   when a task asks for it. Never touch `Visuals/` (the Captain's own drawings).
   Style: [DEV_GUIDES/ART_DIRECTION.md](DEV_GUIDES/ART_DIRECTION.md).
8. **Testing scales with risk.** Cosmetic: focused suites
   (`godot --headless --path . res://tests/test_runner.tscn -- --only=a,b`).
   Central systems or saves: the full runner plus save compatibility. Major
   iteration: full regression. Investigate intermittent failures; never weaken
   a test to get green. Linux results are not Windows acceptance.
9. **Documentation.** Adding, removing or materially changing a `.gd` file
   means updating its entries in the three GDScript guides, then
   `python3 tools/docs/check_gdscript_guides.py` (acknowledge reviews) and
   `python3 tools/docs/check_links.py`. Content: `python3 tools/qa/check_game_content.py`
   must report 0 FAIL.
10. **Performance.** Measure before optimizing (`tests/benchmark_wrs.tscn`,
    same-session before/after); separate render, UI, simulation and loading
    costs; record findings in `docs/technical/PERFORMANCE_OPPORTUNITIES.md`.
    Don't reintroduce per-frame theme rebuilds.
11. **Stop and ask** before: a save-format change, a destructive or
    history-rewriting Git action, pushing to a branch the task didn't name,
    deleting assets or the Captain's art, starting a numbered iteration that
    wasn't commissioned, a conflict where either side loses behaviour, or
    anything that would change gameplay in a visual task.
12. **Delivery report:** version, final commit SHA and branch (verified
    remotely), what changed, tests run and their results (skips stated),
    the [release checklist](docs/technical/RELEASE_READINESS.md) where it
    applies, Windows checks still pending, known limitations, and the
    clickable branch link last.
