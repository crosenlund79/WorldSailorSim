# The Harbourmaster's Inspection: report

Automated content quality and regression safeguards. A quality-assurance pass,
not a gameplay iteration: **no gameplay, interface, save format or game data was
changed.** Version stays 0.108a, save format 12.

## 1. Commits

| | Commit |
|---|---|
| Starting point (I021 complete) | `04a76231581f5a6d0af22ce2c2c138842b869453` |
| The checker | `6317dac` |
| Checker: the Captain's original drawings exempt from the unused list | `76da6b3` |
| Documentation (this report, release readiness, testing guide, orders) | `5142a3f` |
| Final test count in this report | the branch head |

No backup branch was moved or created by this pass (the three existing ones are
unchanged); nothing was force-pushed.

## 2. The checker

`tools/qa/check_game_content.py`: Python 3 only (standard library), no Godot and
no network, about five seconds, Windows and Linux. It reads the game's own source
files (the harbour list and port files, `harbour_looks.json`, `fishing.json`,
`trades.json`, the vessel and companion resources, `locale/da.po` and the
template) and reuses the existing tools rather than duplicating them: the `.po`
parser and placeholder rule of `tools/i18n/check.py`, and the extraction of
`tools/i18n/extract.py` to see whether the template is up to date.

**Results.** Each finding is FAIL (a confirmed defect: the tool exits 1), WARN
(worth a look; the game works) or INFO (for review only), and names the source
file and the offending entry, e.g.

```
FAIL harbour looks: data/harbours/harbour_looks.json [kiel] marked special but has no illustration of its own
```

`--json FILE` writes the same as a machine-readable report (`result`, `checks`
with counts and results, `counts`, `findings`). `--verbose` also lists the
passing checks.

**Run it**

- Windows (from the project folder, in Command Prompt or PowerShell):
  `py tools\qa\check_game_content.py` (or `python tools\qa\check_game_content.py`)
- Linux / macOS: `python3 tools/qa/check_game_content.py`

It is now part of the test workflow ([testing guide](../testing/README.md)), of
the [release checklist](RELEASE_READINESS.md), and a working rule in the
Captain's Orders (run before every delivery; no FAIL).

**Intentionally absent is not a defect.** Three files the game reads only when
they exist are listed with their reason and reported as INFO: `build_info.json`
(written before an export), `data/navigation/depth/depth.bin` (an optional depth
model, none in this build) and `data/navigation/world/land.json` (the generator's
source; the shipped `land.res` is used). Chart rasters are large on purpose
(INFO, not WARN). The Captain's own original drawings in `Visuals/` are kept on
purpose and never listed as unused.

**Files that would not ship.** Inside a git checkout, a file that exists locally
but is ignored by git counts as missing: it would not be in the repository or
in the Captain's ZIP download. (This is how `land.json` was noticed: a run on a
clean copy of the repository found it missing, a run in the working folder did
not.)

## 3. Systems and entries checked (on the I021 build)

| System | Check | Entries | Result |
|---|---|---|---|
| Localization | template up to date with code and data | 2,373 messages | PASS |
| | every message translated (no missing or empty Danish entry) | 2,373 | PASS |
| | placeholders, spacing and line breaks kept | 2,373 | PASS |
| | no duplicate entries in `da.po` | 2,455 entries | PASS |
| | unused Danish entries | 2,455 | PASS (82 INFO) |
| Harbours | unique, well-formed ids | 239 | PASS |
| | list, port files and catalogue in step | 239 | PASS |
| | one harbour per name and country | 239 | PASS |
| | positions on the chart | 239 | PASS |
| | known sea areas (those of `test_harbours`) | 239 | PASS |
| | a sentence about each | 239 | PASS |
| | facility files (only real harbours, only known true/false fields) | 77 files | PASS |
| | harbours named by other data (Go Ashore events) exist | 2 | PASS |
| | names and sentences in Danish | 239 | PASS |
| Harbour looks | every look has its picture and Danish name | 9 looks | PASS |
| | every harbour has a known look | 239 | PASS |
| | special harbours exactly those with their own art (files, titles, reasons in Danish) | 6 | PASS |
| Fish | unique ids | 26 species | PASS |
| | sizes (0 < min < max), rarities, prices (0 only for sharks), strength | 26 | PASS |
| | real sea areas, known lures; every sea area has fish | 26 | PASS |
| | Danish names | 26 (+ 3 junk) | PASS |
| | pictures (body, tail, lid, thumb; junk art) | 29 | PASS |
| Boats | every catalogue entry complete: definition, scenes, profiles, every file they refer to, the six companion spots in each cabin | 4 | PASS |
| Cabin things | unique, positive whole-number prices, a place (floor/wall/shelf), a drawing, names and texts in Danish; sail cloths' names in Danish | 9 (+ 3 cloths) | PASS |
| | nothing owned in a new game | 1 | PASS |
| Companions | every kind's poses and sounds exist | 2 kinds | PASS |
| | every petting line in Danish | 22 lines | PASS |
| | names and genders | — | INFO: not in the game yet |
| Assets | no broken `res://` paths in game files | 857 paths | PASS |
| | texture sizes (≤ 4096 px, ≤ 8 MB) | 201 images | PASS |
| | unused images (for review) | 201 | PASS |

**31 checks, 31 PASS, 0 WARN, 0 FAIL; 7 INFO findings.**

## 4. Errors detected and corrected

None. The I021 build has no integrity defect the checker can see, so no game
data was changed (no geography, fish balance, prices or artwork assignments
were touched). The one apparent defect (`land.json`) turned out to be a
deliberate design: it is recorded as optional, with the reason.

**The checker itself was tested by planting defects.** On a scratch copy of the
repository, 21 defects were planted one at a time and each was caught (FAIL,
exit code 1): a duplicate harbour id, a bad facility value, facilities for a
harbour that does not exist, a harbour without a look, a missing look picture, a
special harbour without its own art, own art not marked special, a missing fish
picture, a fish in an unknown sea, a fish with min weight above max, an unknown
rarity, an empty Danish entry, a lost placeholder in Danish, a duplicate Danish
entry, an out-of-date template, a cabin thing never drawn, a negative price, a
boat's missing cabin scene, a companion's missing pose, an untranslated petting
line, and a broken resource path.

## 5. Remaining findings (all INFO; nothing to fix now)

| Finding | Why it is left |
|---|---|
| 82 Danish entries the game no longer uses (e.g. `Fish%d`) | Harmless; pruning is cosmetic and can be done with the next translation pass |
| The companion has no name or gender | A design gap, not a defect: the Engine Room's petting lines already use them when added (see I021 report §10) |
| `build_info.json`, `depth.bin`, `land.json` absent from the repository | Optional by design (see §2) |
| `europe_navmask.png` (3720 × 4236) and `world/navmask.png` (4320 × 2943) above 4096 px | Chart rasters read as data, large on purpose |

## 6. Tests and results

- The checker on the final build: 31 checks PASS, exit code 0; also run with a
  Windows console encoding (`cp1252`) to make sure an unusual letter in a
  harbour name ("Kuşadası") cannot crash it.
- The 21 planted defects: 21 caught.
- `test_dev_guides` (every link and path in the developer guides and linked
  documents, including the new pages), `test_localization` and
  `test_wider_world`, run on this pass's documentation commit: **158 checks
  passed, 0 failed**.
- `check_links.py` and `check_gdscript_guides.py`: pass (the checker is Python,
  so the GDScript guides needed no change).
- The full regression of the I021 build just before this pass: 74 suites,
  4,762 checks, 0 failed (I021 report). No game file changed since.

## 7. Content not yet covered

- **Behaviour.** Routes, approaches to open water, mooring, catching, saving and
  loading are checked by the Godot suites, not by this file-level tool.
- **Art quality.** The checker sees that a picture exists, not whether it is good.
- **Scenes in depth.** Boat scenes are checked for their files and the
  companion spots; stations, collision and walkable outlines are left to the
  Godot suites (`test_vessels`, `test_boat_of_your_own`, ...).
- **Other catalogues** without integrity problems so far: Go Ashore event texts,
  objectives and awards, weather presets, the chandlery upgrades' effects, the
  Sprite Workshop manifests (they have their own check: `tools/art/build_index.py
  --check`).
- **Audio files**: their paths are checked; their content and length are not.
- **Unused audio and fonts**: only images are listed as unused.

## 8. Gameplay and saves unchanged

This pass added a Python tool and documentation only. No `.gd`, `.tscn`, `.tres`,
`.json` game data, translation or asset file was changed; the save format is
still 12 and the version 0.108a. **Windows was not tested** (the checker is
written to run there; the Captain's own run is the confirmation).
