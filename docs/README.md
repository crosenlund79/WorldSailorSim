# The Ship's Library — Little Captain's Hat

Every report, assignment, requirement tracker and Windows checklist in the game's history, grouped by release so the whole story of one release sits in one folder. The authoritative record of the Captain's decisions stays at the top of the repository: [CAPTAINS_ORDERS.md](../CAPTAINS_ORDERS.md).

## Where we are

- **Current development version: 0.105b**, save format 12. This is [Revision 0.105b, Safe Harbours, Deep Waters & the Sprite Workshop](revisions/v0.105b/).
- **Latest revision:** [report](revisions/v0.105b/REVISION_0_105B_REPORT.md), [requirement tracker](revisions/v0.105b/REVISION_0_105B_REQUIREMENTS.md), [Windows acceptance checklist](revisions/v0.105b/WINDOWS_ACCEPTANCE_0_105B.md) (pending), and the Captain's [assignment](revisions/v0.105b/REVISION_0_105B_ASSIGNMENT.md).
- **Next planned iteration: Iteration 19, The Captain's Watch.** It is planned but **not started and not implemented**. Iterations 20 (A Boat of Your Own) and 21 (The Well-Trimmed Ship) are also planned. Their scope is set by the Captain; see [CAPTAINS_ORDERS.md](../CAPTAINS_ORDERS.md).

## Iterations

| Iteration | Version | Documents |
|---|---|---|
| [001](iterations/i001/) Core Game Foundation & Visual Identity | — | [report](iterations/i001/ITERATION_001_REPORT.md) |
| [002](iterations/i002/) The First Voyage | — | [report](iterations/i002/ITERATION_002_REPORT.md) |
| [003](iterations/i003/) Wind, Sails & Propulsion | — | [report](iterations/i003/ITERATION_003_REPORT.md), [003b](iterations/i003/ITERATION_003B_REPORT.md), [003b UI hotfix](iterations/i003/ITERATION_003B_UI_HOTFIX_REPORT.md) |
| [004](iterations/i004/) The Boatyard & Sprite-Ready Vessel Architecture | — | [report](iterations/i004/ITERATION_004_REPORT.md), [004b](iterations/i004/ITERATION_004B_REPORT.md) |
| [005](iterations/i005/) The Dangerous Sea | — | [005a](iterations/i005/ITERATION_005A_REPORT.md), [005b](iterations/i005/ITERATION_005B_REPORT.md), [005c](iterations/i005/ITERATION_005C_REPORT.md), [Windows acceptance](iterations/i005/WINDOWS_ACCEPTANCE_I005.md) |
| [006](iterations/i006/) Making Waves | — | [report](iterations/i006/ITERATION_006_REPORT.md), [Windows acceptance](iterations/i006/WINDOWS_ACCEPTANCE_I006.md) |
| [12](iterations/i012/) A Little Harbour Life | 0.100c | [report](iterations/i012/ITERATION_12_REPORT.md), [Windows acceptance](iterations/i012/WINDOWS_ACCEPTANCE_12.md) |
| [13](iterations/i013/) The Catch & The Cove | 0.101a | [report](iterations/i013/ITERATION_13_REPORT.md), [Windows acceptance](iterations/i013/WINDOWS_ACCEPTANCE_13.md) |
| [14](iterations/i014/) A Bigger World, a Better Boat | 0.102a | [report](iterations/i014/ITERATION_14_REPORT.md), [Windows acceptance](iterations/i014/WINDOWS_ACCEPTANCE_14.md) |
| [16](iterations/i016/) The World Awaits | 0.103a | [report](iterations/i016/ITERATION_16_REPORT.md), [Windows acceptance](iterations/i016/WINDOWS_ACCEPTANCE_16.md), [Shipyard Efficiency](iterations/i016/SHIPYARD_EFFICIENCY_16.md) |
| [17](iterations/i017/) Let There Be Light | 0.104a | [assignment](iterations/i017/ITERATION_17_ASSIGNMENT.md), [report](iterations/i017/ITERATION_17_REPORT.md), [requirements](iterations/i017/ITERATION_17_REQUIREMENTS.md), [Windows acceptance](iterations/i017/WINDOWS_ACCEPTANCE_17.md) |
| [18](iterations/i018/) The Joy of the Journey | 0.105a | [assignment](iterations/i018/ITERATION_18_ASSIGNMENT.md), [report](iterations/i018/ITERATION_18_REPORT.md), [requirements](iterations/i018/ITERATION_18_REQUIREMENTS.md), [Windows acceptance](iterations/i018/WINDOWS_ACCEPTANCE_18.md) (pending) |
| [19](iterations/i019/) The Captain's Watch | 0.106a | [report](iterations/i019/ITERATION_19_REPORT.md) (traffic, radar, anchor alarms, VHF, English and Dansk; Windows acceptance pending) |
| [20](iterations/i020/) A Boat of Your Own | 0.107a | [report](iterations/i020/ITERATION_20_REPORT.md) (fishmonger, chandlery, sailmaker, cabin things; Windows acceptance pending) |
| [Real Horizon](iterations/real_horizon/) Illustrated Mariner visual fork | 0.107a | [report](iterations/real_horizon/REAL_HORIZON_REPORT.md) (visual-only conversion; gameplay unchanged) |

Iterations 7–11 have no separate documents in this repository. Iteration 15 (the performance pass) was skipped at the Captain's instruction.

## Revisions

| Revision | Documents |
|---|---|
| [0.100a](revisions/v0.100a/) Visual Identity V01: A Little Personality | [report](revisions/v0.100a/VISUAL_IDENTITY_V01_REPORT.md), [Windows acceptance](revisions/v0.100a/WINDOWS_ACCEPTANCE_VISUAL_V01.md) |
| [0.100b](revisions/v0.100b/) A Living Little World | [report](revisions/v0.100b/VISUAL_POLISH_0100B_REPORT.md) |
| [0.102b](revisions/v0.102b/) Life at Anchor | [report](revisions/v0.102b/REVISION_0_102B_REPORT.md), [Windows smoke test](revisions/v0.102b/WINDOWS_SMOKE_0_102B.md) |
| [0.105b](revisions/v0.105b/) Safe Harbours, Deep Waters & the Sprite Workshop | [assignment](revisions/v0.105b/REVISION_0_105B_ASSIGNMENT.md), [report](revisions/v0.105b/REVISION_0_105B_REPORT.md), [requirements](revisions/v0.105b/REVISION_0_105B_REQUIREMENTS.md), [Windows acceptance](revisions/v0.105b/WINDOWS_ACCEPTANCE_0_105B.md), [evidence logs](revisions/v0.105b/evidence/) |

## Design and technical references

- [Architecture](technical/ARCHITECTURE.md): how the game is built, including route calculation.
- [The Captain's Chartroom UI pass](technical/CAPTAINS_CHARTROOM_UI_PASS.md): the shared day/night interface theme (Vintage Chartroom and Harbor Dusk), what the HUD and chart show by default, and the *Interface light* setting.
- [Cozy Polish injection report](technical/COZY_POLISH_INJECTION_REPORT.md): floating things at sea, the chart's zoom limit, the Kiel and Suez canals, the Q menu, coffee and the hat in hand, the remembered sleep, visited-harbour pins, compact panels and the loading screen.
- [The Well-Run Ship performance report](technical/THE_WELL_RUN_SHIP_PERFORMANCE_REPORT.md): where the time went (the day/night theme stall), what is kept in memory and what is written to disk, the sleep, dawn and dusk cards, and Long Passage on the voyage map.
- [Turbocharge performance report](technical/TURBOCHARGE_PERFORMANCE_REPORT.md) and the permanent [Performance Opportunity Register](technical/PERFORMANCE_OPPORTUNITIES.md): what was measured, what was optimized, and the ranked list of what could be done next.
- [Localization](technical/LOCALIZATION.md): English and Dansk, how text is translated, the tools and the glossary.
- **The Engine Room, the GDScript guides:** every script in the game, one entry each. [For the Captain, in English](technical/GDSCRIPT_GUIDE_EN.md), [for the Captain, in Danish](technical/GDSCRIPT_GUIDE_DA.md), and [the developer architecture reference](technical/GDSCRIPT_ARCHITECTURE.md) (dependencies, signals, state, invariants, tests, cross-system flows). Kept current with `python tools/docs/check_gdscript_guides.py`. How they were made, the companion's kind words, and the two test-reliability fixes: [Engine Room & Companion Polish report](technical/ENGINE_ROOM_AND_COMPANION_POLISH_REPORT.md).
- [Developer guides](../DEV_GUIDES/README.md): step-by-step guides for art, companions, audio, weather, harbours, boat care, chart regions and life aboard, plus design principles for future user content ([MODDING_FUTURE.md](../DEV_GUIDES/MODDING_FUTURE.md)). They stay in `DEV_GUIDES/` because the game's in-game guide viewer reads them from there.

## Testing

- [Cross-iteration testing guide](testing/README.md): the automated test runner, the restart, screenshot and benchmark harnesses, and the documentation link check.
- Windows acceptance checklists live with their iteration or revision (see the tables above).

## Artwork and the Sprite Workshop

- [Sprite Workshop: start here](../art_replacements/README_START_HERE.md) (for the artist) and its [index](../art_replacements/INDEX.md).
- [Sprite Workshop report](artwork/SPRITE_WORKSHOP_REPORT.md): audit, sizes, priorities and counts.
- [Art pipeline](artwork/ART_PIPELINE.md): where the art instructions live.
- [Original soundtrack](artwork/ORIGINAL_SOUNDTRACK_REPORT.md): the three pieces (*Home Upon the Waves*, *The Wind Knows the Way*, *Lanterns Across the Water*), how they were composed and rendered, their licence, and how the game chooses between them. Sources are in `tools/music/`.

## Benchmarks and screenshots

- [Benchmarks](benchmarks/): JSON results by iteration and revision. Revision 0.105b's files record version, commit and label.
- [Screenshots](screenshots/): by iteration (`iteration12/` … `iteration18/`) and revision (`revision_0102b/`, `revision_0_105b/`), plus the interface pass (`chartroom_ui/`). The older screenshots from before Iteration 12 are at the top of the folder.

## About this library

The documents were moved here from the repository root by the Ship's Library side quest. The full old → new mapping is in [DOCUMENTATION_REORGANIZATION_REPORT.md](DOCUMENTATION_REORGANIZATION_REPORT.md). Run `python3 tools/docs/check_links.py` to check every internal link.
