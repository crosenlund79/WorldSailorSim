# Testing across iterations

How Little Captain's Hat is tested, from Iteration 001 to today. Each release's own results are in its report in the [Ship's Library](../README.md). This page describes the tools they all share.

## The automated test runner

```sh
godot --headless --path . res://tests/test_runner.tscn                      # every suite
godot --headless --path . res://tests/test_runner.tscn -- --only=anchorage  # suites whose file name contains "anchorage"
godot --headless --path . res://tests/test_runner.tscn -- --only=chartroom,cockpit   # several, comma-separated
godot --path . res://tests/test_runner.tscn -- --screenshots=/some/dir      # rendered, saving screenshots (e.g. under Xvfb)
```

- The suites are in `tests/suites/` and listed in `tests/test_runner.gd`. Shared helpers are in `tests/helpers/`: walkability flood fill, the reel helper, and the Sprite Workshop art fixtures.
- Tests use scratch saves and settings (`user://test_saves`, `user://test_settings.cfg`) and never touch the player's own.
- The exit code is 0 only if every check passed. The latest full results (check counts, run time) are in the newest release report.

## Harnesses that run outside the runner

Each is a scene in `tests/` with the exact command in its header comment.

| Kind | Scenes | What they show |
|---|---|---|
| Restart (two separate processes) | `restart_check`, `restart_17`, `restart_18`, `restart_105b` | Saves and settings survive quitting and starting again. Run `--phase=write`, then `--phase=read` (0.105b adds the art install/import/remove phases). |
| Screenshots | `screenshots_16`, `screenshots_17`, `screenshots_18`, `screenshots_105b`, `screenshots_chartroom` (every main screen by day and by night) | Rendered evidence for each release, written to `docs/screenshots/…` or a given folder. |
| Benchmarks | `benchmark`, `benchmark_17`, `benchmark_18`, `benchmark_105b`, `benchmark_wrs` (sleep, dawn and dusk, the chart, Long Passage and growth over a session; `--presented` for the new presentations) | Frame times under a software renderer, for before/after comparison only. Results are in [docs/benchmarks](../benchmarks/). |
| Measurements | `pacing_18`, `cabin_light_18` | Long Passage stop counts; cabin light and shadow figures. |

## Windows acceptance

Every release has a checklist for the Captain's own Windows trial, kept in that release's folder (for example [0.105b](../revisions/v0.105b/WINDOWS_ACCEPTANCE_0_105B.md) and [Iteration 18](../iterations/i018/WINDOWS_ACCEPTANCE_18.md)). Acceptance is never claimed before the Captain's own results come back.

## Content check (the Harbourmaster's Inspection)

```sh
python3 tools/qa/check_game_content.py                 # Linux / macOS
py tools\qa\check_game_content.py                      # Windows (or: python tools\qa\check_game_content.py)
python3 tools/qa/check_game_content.py --verbose       # every check, also the passing ones
python3 tools/qa/check_game_content.py --json qa.json  # machine-readable report
```

Reads the game's data files (no Godot, no network, about five seconds) and checks
that harbours, harbour looks and special harbours, fish, boats, cabin things,
companions, the Danish catalogue and the asset paths hang together. Findings are
FAIL (a confirmed defect; exit code 1), WARN (worth a look) or INFO (for review
only, such as unused images; nothing is ever deleted), each with its file and
entry. Run it after adding or changing content, and before every delivery; the
Godot runner then checks behaviour (routes, mooring, catching, saves). See
[RELEASE_READINESS.md](../technical/RELEASE_READINESS.md) and
[the inspection report](../technical/HARBOURMASTERS_INSPECTION_REPORT.md).

## Operation One Clock sea trial

Where the frame time goes at 1×, 5× and 20×, at night, at dawn and dusk and in
harbour. In Godot open `tests/one_clock_sea_trial.tscn` and press F6 (about five
minutes; the table is shown, copied to the clipboard and saved as
`one_clock_sea_trial.txt`). Developers: `xvfb-run -a godot --path .
--rendering-driver opengl3 --resolution 1600x900 res://tests/one_clock_sea_trial.tscn
-- --all --out=/tmp/one_clock.json`. See
[the investigation](../technical/ONE_CLOCK_PERFORMANCE_INVESTIGATION.md).

## Documentation checks

```sh
python3 tools/docs/check_links.py   # every internal Markdown link and #heading anchor resolves
```

`test_dev_guides` also checks every link and repository path in the developer guides and in a set of linked documents.

## The Illustrated Catalogue's contact sheets

Picture sheets of all the game's art, for looking, not for pass/fail (see
[the catalogue](../art/ILLUSTRATED_ASSET_CATALOGUE.md)):

```sh
# the art the game draws in code, photographed through the game (needs a display)
xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 \
  res://tools/art/capture_previews.tscn -- --out=docs/art/previews
python3 tools/art/build_contact_sheets.py   # six sheets in docs/art/contact_sheets/ (Pillow)
```
