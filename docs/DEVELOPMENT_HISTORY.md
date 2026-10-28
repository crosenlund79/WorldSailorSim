# Development history

Little Captain's Hat is one continuous project in two repositories. Their Git
histories are shared up to I023 (WorldSailorSim was created by GitHub Import,
so the old commits are the same objects), but they are separate repositories
and are never merged back into one chain.

| | Repository | Role |
|---|---|---|
| Original | <https://github.com/crosenlund79/LittleCaptainsHat> | Development up to I023; read-only history, to be archived by the Captain |
| Canonical | <https://github.com/crosenlund79/WorldSailorSim> | All development from the Great Handover on |

## Milestones

| Milestone | Version | Where | Key SHA |
|---|---|---|---|
| I020 A Boat of Your Own: cabin personalization, harbour services | 0.107a | both | `backup/post-engine-room-pre-i021` = `ec84cfa466defea556c64bf3335c9c659f35eaea` (after I020 and the Engine Room) |
| I021 A Wider, Warmer World | 0.108a | both | `release/i021` = `04a76231581f5a6d0af22ce2c2c138842b869453` |
| I022 The Captain's Other Life | 0.109a | both | `release/i022` = `2baa01034fbaa956018c58e013b555be8213d77d` |
| I023 Steady Hands & Golden Harbours | 0.109a | original only | `release/i023` = `d4e2e7e56206b220f8839323186e0c06d2a4c589`; original integration head `claude/friendly-fermat-dey23f` = `81d2526655352b6172d9941ce532f620d5d5050b` (I023 + docs) |
| Real Horizon visual conversion (not numbered) | 0.109a | WorldSailorSim | built on `ec84cfa`; conversion tip `bbdadfadf17fc50a56a1a2e389ba2c92b8c2ff1d` |
| Great Handover (Operation New Horizon, not numbered) | 0.109a | WorldSailorSim | merge of `81d2526` into Real Horizon: `9b3c44f650ad9d7e887e7832c8c3ab9899da2845`; the handover ends at the head of `claude/friendly-fermat-dey23f` after its fast-forward (this commit or the next docs-only one) |
| I024 The Company We Keep: living companions (Ragdoll, Pug, parrot), shore visits, the achievement collection, the cabin laptop | 0.110a | WorldSailorSim | started at `41130c04e168239a082202f3d147ace543620f55`; `release/i024` at the final tested commit ([report](iterations/i024/ITERATION_24_REPORT.md)) |
| Build identifier (small adjustment after I024) | 0.110a | WorldSailorSim | the bottom-right `LCH · i024 · DEV` label from `GameVersion`; on `claude/captains-hat-visual-redesign-cgoy5o` |
| I025 | — | WorldSailorSim | next major iteration, not yet commissioned |

## The Great Handover (2026-10-28)

**Starting state.** WorldSailorSim was imported with every branch of the original
at that time except `iteration/i023`/`release/i023` and the original's last
integration commits; its default branch was `backup/post-engine-room-pre-i021`
(`ec84cfa`), its `claude/friendly-fermat-dey23f` stood at I022 (`2baa010`). The
Real Horizon conversion (`claude/captains-hat-visual-redesign-cgoy5o`) had been
built on `ec84cfa`, i.e. **before I021**: it lacked I021, the Harbourmaster's
Inspection, Operation Paperwork / One Clock, I022 and I023.

**What was done.** The original's integration head `81d2526` (fetched read-only)
was merged into Real Horizon with a normal merge commit. Six text conflicts
were resolved keeping both sides (Real Horizon visuals with I021 harbour looks,
I022's loading-screen intent, I021 fish in the new painter, I021 cabin things in
the new palette, the docs index, the translation template). Everything visual
that arrived with I021–I023 was converted to Real Horizon: the nine harbour
looks and six special harbours repainted top-down, all 29 catches repainted
(fish geometry data unchanged), the cabin-window views, the Golden Harbour
arrival card, postcard skies. No gameplay code was rewritten.

**Feature parity.** All I021–I023 behaviour is present by merge (not
re-implementation): harbours and harbour looks, special harbours, new fish and
cabin things, the brass compass, the content checker, One Clock, separate wind
volume, boat prices and ownership, difficulty settings, postcards, the game
developer pastime, the Captain's Academy and Handbook, cabin windows (Starling
33), softer water, Steady Hands UI fixes (Trip Details, fit-to-screen windows,
Esc, Danish layout sweep, dusk readability) and the Golden Harbour moment. The
full regression result is under Results below.

**Deliberate differences from the original.** The look (Real Horizon). The
loading screen shows the menu's painted title scene instead of a navy
gradient (same intent: the start looks like the menu). WaterLook still sets
the water colour, but the Real Horizon sea shader draws the final water.

**Results.**
- Full regression on the merged build (`9b3c44f`): 5001 checks passed, 0
  failed, no script errors. Content checker 31/31 PASS; English/Danish 2611
  messages, 0 errors; GDScript guides (309 scripts) and links pass.
- Saves: `SAVE_VERSION` 12 unchanged. `src/persistence`, `SessionState`,
  `GameSession` and every simulation folder are byte-identical to
  `release/i023`, so an I023 save loads exactly as it did there; the 69 `src/`
  files that differ from I023 are presentation only.
- Performance (same session, Linux software rendering): chart, simulation,
  sleeps and memory unchanged; deck scenes 20–55 % slower per frame, likely
  the sea shader's fill cost on a CPU rasterizer. Recorded as #10 in
  [PERFORMANCE_OPPORTUNITIES.md](technical/PERFORMANCE_OPPORTUNITIES.md); a
  Windows reading decides whether anything changes.
- Windows acceptance pending:
  [WINDOWS_ACCEPTANCE_HANDOVER.md](iterations/real_horizon/WINDOWS_ACCEPTANCE_HANDOVER.md).
