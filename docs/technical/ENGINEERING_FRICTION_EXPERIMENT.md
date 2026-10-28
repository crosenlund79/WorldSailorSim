# Operation Paperwork: one small change, where does the time go?

One-time measurement: adding a **brass compass** cabin thing (decor id
`compass`, €55, wall), done properly, with every required check.

### Time spent

| Activity | Minutes | % of total |
|---|---:|---:|
| Understanding | 0.6 | 2.0 % |
| Implementation | 0.1 | 0.3 % |
| Localization | 0.1 | 0.5 % |
| Tests | 22.0 | 76.8 % |
| Guardrails | 0.3 | 1.0 % |
| Documentation | 1.9 | 6.6 % |
| Git and delivery | 0.4 | 1.3 % |
| Rework | 3.2 | 11.4 % |
| **Total** | **28.6** | **100%** |

- **Direct feature work** (implementation + localization): 0.2 min (1 %).
- **Supporting work** (tests + guardrails + documentation + Git): 24.6 min (86 %).
- **Understanding and rework:** understanding 0.6 min (2 %), rework 3.2 min (11 %).
- **Command/wait time** (already inside the categories): 22.1 min (77 %): 21.8 min measured
  (Godot runs: 19.9 of them the full regression), about 0.3 min of quick Python
  checks estimated.
- **Unmeasured / excluded:** 3.8 min waiting for the Captain's decision
  (below) is excluded; this report's own commit and push happened after the
  table was fixed (stated in the delivery message).

**What happened.** The first version took under a minute: one data entry, one
drawing function, two Danish lines. The focused cabin test then failed: with
all ten things shown, the Arctic Wanderer 26 and the Clam 40 had wall room for
only seven wall things, so the compass would not have appeared on two of four
boats. The fix needed the Captain's choice ("make room"): a second placement
pass for left-over things (from inside each hull, then slightly closer). The
first pass is unchanged, so nothing already placed moved. That was the rework.

### Assessment

- **Most time:** tests, and within them the full regression (19.9 min wall, of
  which none was active work). The change itself was about a minute.
- **Most expensive checks:** the full regression (1,191 s); then the rendered
  preview capture for the catalogue (49 s). Every other guardrail (GDScript
  guide freshness, content checker, links, translations) took seconds.
- **Meaningful protection:** the focused suite `test_boat_of_your_own` (13 s)
  found the one real defect, before anything was committed. The translation
  check and guide checker are cheap and kept English, Danish and the guides
  in step. The full regression found nothing (4,767 passed).
- **Disproportionate:** a 20-minute full regression for a decorative item that
  touches one drawing script, one data file and one test; the catalogue's
  previews and sheets also had to be refreshed by hand.
- **Suggestions (no safeguard was relaxed here):** (1) for a small content
  addition, run the content checker plus the suites that cover the touched
  files, and run the full regression on a schedule and before every iteration
  release; (2) let the content checker warn when the cabin-thing list exceeds
  the smallest cabin's room, so the capacity problem shows before coding.

### Evidence

- Commits: start `47b5e7e0c51f53e4ebff39058d10a6db87f0c84e`; change
  `7b69166cccb1694b909476ce298409daf2ca6115` (19 files, +101/−34: 6 game and
  test files +82/−15, 13 docs and previews +19/−19); this report afterwards.
- Runs: `test_boat_of_your_own` ×3 (fail 4 → fail 3 → 57/57 pass), probe
  scene ×4 (temporary, deleted), rendered capture ×1, full regression ×1
  (4,767 passed, 0 failed; one launch failed instantly on a missing `time`
  binary and was relaunched), `extract.py` + `check.py` (2,375 messages, 0
  errors), `check_gdscript_guides.py` (282 scripts), `check_game_content.py`
  (31 PASS, 0 FAIL), `check_links.py` (0 broken).
- Verified: bought and shown on all four boats (10 of 10 placed, none on a
  station, no collision), Danish name, owned things survive save/load (the
  suite's save round trip), screenshots of the two smaller cabins checked.
- **Limitations:** one person and one AI session, one change; timestamps were
  written at the start of each command, so the time spent composing a command
  falls in the interval before it (for example, writing the first version
  counts partly as understanding); an interval in which two things ran
  together is counted once, as the active work; the regression's duration
  depends on this machine.

Log: [ENGINEERING_FRICTION_LOG.txt](ENGINEERING_FRICTION_LOG.txt).
