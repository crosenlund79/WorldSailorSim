# Release readiness: a checklist for every build

A short, reusable list for any delivery of Little Captain's Hat (an iteration, a
revision or a maintenance pass). Copy the table into the delivery report and fill
in the right-hand column; "not run" is an honest answer, a guess is not.

Commands are given for Linux; on Windows use `py` (or `python`) for the Python
tools and the Godot executable's own name.

| # | Area | How | Ready when |
|---|---|---|---|
| 1 | **Content integrity** | `python3 tools/qa/check_game_content.py` | 0 FAIL. Every WARN read and either fixed or explained in the report; INFO reviewed (unused images are kept until the Captain decides) |
| 2 | **English and Danish** | `python3 tools/i18n/extract.py`, then `python3 tools/i18n/check.py`; `test_localization` | Every message translated, placeholders kept, 0 errors; the template committed with the code; new Danish names that are uncertain listed in the report |
| 3 | **Missing assets** | Part of (1): broken `res://` paths, missing pictures for harbours, fish, boats and companions; then `godot --headless --path . --import` with no "Failed loading" errors | Nothing missing; git-ignored files are never counted on |
| 4 | **Saves** | `SaveManager.SAVE_VERSION` unchanged unless the Captain approved a change; the save suites (`test_save_manager`, `test_voyage_persistence`, and the iteration's own suite) | An old save loads where it was; new content starts unowned or undiscovered |
| 5 | **Core gameplay** | `godot --headless --path . res://tests/test_runner.tscn` (all suites) | All checks pass. A failure seen only in a busy or partial run is re-run alone and compared with the previous build before it is called noise |
| 6 | **Performance smoke test** | `xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/benchmark_wrs.tscn -- --out=after.json --turbo`, against the previous build measured **in the same session** | No scenario clearly worse beyond the machine's usual drift (3–10 %); memory over a 20-round session flat. Update the [Performance Opportunity Register](PERFORMANCE_OPPORTUNITIES.md) when something was measured |
| 7 | **Documentation** | `python3 tools/docs/check_gdscript_guides.py` and `python3 tools/docs/check_links.py` | Both pass; the release has its report and is in the [library index](../README.md) and the Captain's Orders |
| 8 | **Windows acceptance** | The release's `WINDOWS_ACCEPTANCE_*.md` checklist | Written for the Captain; marked **pending** until the Captain's own trial. Never claimed in advance |
| 9 | **GitHub backup** | Before the work starts: a `backup/…` branch at the starting commit, verified with `git ls-remote origin` (and the GitHub branch list); after it: the development branch's remote head equals the final commit. A major iteration instead works on `iteration/iNNN` and ends with `release/iNNN` at its final commit ([Captain's Orders](../../CAPTAINS_ORDERS.md), *Major iteration branches*) | The backup or release branch exists at the recorded SHA; existing backups and releases untouched; no force-push |
| 10 | **Known issues** | The report's limitations section | Every deferral, workaround and uncertain value written down, with what it would take |

## Before you start a build

- Verify the remote head of the development branch and that the working tree is
  clean; read the Captain's Orders and the previous release's report.
- Record a same-session performance baseline before changing anything (step 6).

## After you finish

- Run steps 1–7 on the final commit, push, and verify the remote head.
- The delivery states the version, the final commit, the branch, the report and
  the Windows checklist, and ends with the branch link (Captain's Orders).
