# Companion artwork and poses

How the ship's cat is drawn in the game, and how you change, add or prepare
companion artwork. The general sprite rules are in [SPRITES.md](SPRITES.md).

## What the game does with the companions (I024)

Since I024 (The Company We Keep) there are three companions, chosen at New
Game with an optional name and gender: a **Ragdoll cat** (kind `cat`), a
**Pug** (`dog`) and a **green-cheeked conure**, a small parrot (`parrot`).
Older saves keep their cat or dog, now drawn as the Ragdoll and the Pug.

The art is painted in the Real Horizon style by one command,
`python3 tools/companions/paint_companion_clips.py` (`paint_companions.py`
runs it): short **animated clips**, every frame on the same 256 × 256 px
transparent canvas, facing right, the animal's ground point at the same place
(cat and dog (128, 160), parrot perch (128, 176)). Frames are
`assets/companions/<kind>/<clip>_<NN>.png`; the old single images
(`resting.png`, …) are kept as copies of frame 00. The owner's original cat
drawings stay in `Visuals/Cat/`, unchanged.

| Kind | Clips (frames @ fps, *once* = plays once and holds) |
|---|---|
| cat (Ragdoll) | resting 8@6, walk 8@10, turn 4@10 once, sit 6@5, lie_down 4@8 once, sleeping 6@3, wake 4@6 once, stretching 6@6 once, groom 8@8, alert 4@4 (looks at the Captain), pet 6@6 (petting response), settle 6@6 once (circles and lies down by the berth) |
| dog (Pug) | resting 8@5, walk 8@10, turn 4@10 once, sit 6@5, lie_down 4@8 once, sleeping 6@3, wake 4@6 once, stretching 6@6 once (play bow), tail_wag 6@12, alert 6@6 (head tilt), pet 6@8, settle 6@6 once |
| parrot | resting 6@4, blink 3@10 once, head_turn 6@6 once, hop 6@10 once, takeoff 4@12 once, fly 6@12, land 4@12 once, ruffle 6@10 once (feather settling), preen 8@8, sleeping 4@2, wake 4@6 once, alert 6@8 (interaction response) |

The sets are `data/companions/<kind>_visuals.tres`: one `CompanionPoseArt`
per clip (`image_path` = frame 00, `frames` = the rest, `fps`, `loop`), the
`display_size` (cat 66, dog 56, parrot 50 scene units for the canvas side -
smaller than before, the Captain is about 40 across), the `pivot` (the ground
point) and the movement speeds matched to the drawn stride so the feet do
not slide (`walk_speed`: cat 20.5, dog 11 units/s; `fly_speed` parrot 110).

**Behaviour** (`ShipCompanion`, presentation only, never saved): the logical
pose chooses the clip; short transitions play in between (lie down after a
walk, wake after a nap, settle into a nap by the berth). Between rests the
cat grooms, sits or stretches, the dog wags or sits, the parrot preens,
ruffles, turns its head and blinks. Walking it turns first when it reverses
(the turn clip faces the viewer at its middle, where the drawing is
mirrored) and faces the way it goes. The parrot takes off, flies a little
above the cabin or deck and lands at its perch, or hops a short way.
Petting plays the pet clip; walking up to it plays the alert look. Each clip
change is a short cross-fade.

**Ashore and asleep.** Moored in a harbour the companion follows the Captain
down the gangplank to a place on the pontoon (the parrot flies); the boat
cannot cast off while it is ashore. After sleeping it is found by the berth.

**Replacing art.** A Sprite Workshop replacement of a pose (`<workshop_id>.<pose>`,
e.g. `pet.snovs.resting`, `pet.dog.resting`, `pet.parrot.resting`) replaces
that whole clip with the one drawing (shown still, with the small breathing
swell); the Captain's drawing always wins. The procedural drawings in
`src/companion/ship_companion.gd` remain only as the fallback when a set's
resting image is missing. To see every clip playing, open
`tests/companion_animation_preview.tscn`.

## 1. Where to draw and export

- Put your own exported drawings in **`Visuals/Cat/`** (or a *Visuals/Dog/* folder)
  and point the set's image paths at them (§3). The game's current art is in
  `assets/companions/`; repaint it with `tools/companions/paint_companions.py`.
- Keep working files (`.kra`, `.psd`, layers) outside the project folder, or at
  least outside `Visuals/`.
- Export PNG. Transparent background is best. A plain white (or any single flat
  colour) background also works, as long as it reaches all four edges and the
  cat's outline is closed.

## 2. File and folder rules

- Use exactly these names, including capitals: `Cat_resting.png`,
  `Cat_SleepingBack.png`, `Cat_alert.png`, `Cat_stretching.png`. Linux and
  exported games treat `cat_resting.png` as a different file.
- **Same canvas for every pose.** All four current images are 1254 × 1254 px with
  the cat roughly in the middle. Keep the same canvas size and keep the cat's body
  in the same place, so changing pose does not make it jump.
- **Size.** Draw the cat to fill about 60–70% of the canvas width, like now. The
  game scales the whole canvas down (see §4), so the cat keeps its on-screen size.
- **Smaller exports load faster.** The images are scaled to 320 px when loaded. A
  512 × 512 export looks the same in the game and loads quicker than 1254 × 1254.

## 3. How poses are mapped

The mapping is a data file: **`data/companions/cat_visuals.tres`**. Open it in
Godot (double-click it in the FileSystem dock) and look in the Inspector:

- **Kind**: `cat`.
- **Poses**: a list. Each entry (a `CompanionPoseArt`) has:
  - **Pose**: the name the behaviour uses (`resting`, `sleeping`, `alert`,
    `stretching`);
  - **Image Path**: the PNG, for example `res://Visuals/Cat/Cat_alert.png`;
  - **Offset**, **Scale**, **Flip H**: per-pose placement fixes (see §4).
- **Behaviour** group: rest time (min, max), sleep time (min, max), chance of a
  nap, stretch, alert and cross-fade durations, and how often walking up to it
  makes it look up (`Approach Alert Cooldown`, 0 = never).

The script that runs the behaviour is `src/companion/ship_companion.gd`; the data
types are `src/companion/companion_visual_set.gd` and
`src/companion/companion_pose_art.gd`. **You do not need to edit any of them to
change art or timing.**

## 4. How alignment works

The `Placement` group of `data/companions/cat_visuals.tres` controls it:

- **Display Size** (72): the canvas's longer side is drawn this many scene units
  long. The player token is 40 units across. Raise it to make the cat bigger.
- **Pivot** (0.5, 0.5): the point of the canvas, as a fraction of its width and
  height, placed on the resting spot. (0.5, 0.5) is the centre; (0.5, 0.8) would
  put a point near the bottom on the spot.
- Per pose: **Offset** shifts that pose in scene units (+x right, +y down);
  **Scale** enlarges or shrinks only that pose; **Flip H** mirrors it.

All four images share one canvas, so the current offsets are zero. Use an offset
only when a new drawing sits somewhere else on its canvas.

**Background removal** (`Loading` group):
- `Remove Background` is on.
- `Background Tolerance` (0.12) is how close to the corner colour a pixel must be
  to count as background. Raise it slightly if a light fringe remains; lower it if
  pale parts of the cat disappear.
- Images that already have transparency at their border are used unchanged.

## 5. How petting works

- The cat's interaction (E, prompt "Pet cat") calls `pet()`.
- **Next to a station** (Iteration 005b): a resting cat never takes over a
  station, door or berth the player is standing at. To pet a cat lying right by
  a station, step up to the cat and face it (the arrow on the player token);
  the prompt then says "Pet cat". The rule is in
  `src/interaction/interaction_sensor.gd` (`focus_priority` −1 for the
  companion), so it holds on every boat without per-station exceptions.
- That plays the purr on the SFX bus (`assets/audio/placeholder/companion_purr.wav`,
  see [AUDIO.md](AUDIO.md)), shows the `alert` pose for `Alert Seconds` (at least
  1.6 s) with rising hearts, then returns to `resting`.
- Without an `alert` image, the cat keeps its current image and still purrs and
  shows hearts.

## 6. Change a pose image

Either way, no code changes:

- **Same name:** overwrite `Visuals/Cat/Cat_alert.png` with your new drawing,
  let Godot re-import (focus the editor, or run
  `godot --headless --path . --import`), and run the game.
- **Different name or folder:** put the file in `Visuals/Cat/`, then in
  `data/companions/cat_visuals.tres` select the pose and change **Image Path** to
  the new file. Save.

## 7. Add another pose

The behaviour knows four pose names: `resting`, `sleeping`, `alert`,
`stretching`. With the data file alone you can:

- **give an existing pose a different image** (above);
- **use one image for several poses**: point two entries at the same file;
- **leave a pose out**: delete its entry. The behaviour then skips it, and petting
  keeps the current image.

A **new kind of behaviour** (for example `grooming`) needs one small code change
in `ShipCompanion.advance_behaviour()` (`src/companion/ship_companion.gd`), which
decides when each pose name is used. Add the new entry in the data file first.
The artwork side then works exactly like the four existing poses.

## 8. Check it in Godot

1. Run the project (F5) and start a New Game. The cat appears in the cabin. In
   the New Game dialog the preview also shows its resting image.
2. Walk up to the cat. It looks up briefly (`alert`), unless it is asleep.
3. Press E: purr, hearts and the alert pose, then back to resting.
4. To see the idle poses without waiting, temporarily set `Rest Seconds` to
   (3, 5) in the data file. **Set it back afterwards.**
5. Change boats at the boatyard and go below: the same cat in the same spot.

The automated tests check that all four files load, that the poses line up, the
behaviour and petting, and the fallbacks:

```
godot --headless --path . res://tests/test_runner.tscn -- --only=companion
```

## 9. Diagnose a missing sprite

- **The cat looks like a simple drawn shape (grey, top-down):** the resting
  image could not be loaded. The Godot output panel shows a warning such as
  `Companion art 'cat': pose 'resting' image res://Visuals/Cat/Cat_resting.png is missing or unreadable`.
  Check the name, the capitals and the folder. Make sure the file was imported
  (it has a `.import` file next to it).
- **One pose never appears:** that entry's file is missing (the same warning,
  naming it), and the pose falls back to resting.
- **The old picture still shows after replacing it:** re-import (focus the editor
  or run `--import`) and restart the game. Images are cached while the game runs.
- **White halo or missing parts:** see the background notes in §4 and the table
  in [SPRITES.md](SPRITES.md).

## 10. The dog's artwork

Since Iteration 13 the dog has its own set, `data/companions/dog_visuals.tres`,
with the four poses in `assets/companions/dog/`. To use your own dog drawings
instead, export them (for example into a *Visuals/Dog/* folder) on one square
canvas and point each pose's **Image Path** in that file at them; nothing has
to be programmed.

The dog's sound is `assets/audio/placeholder/companion_dog_pant.wav` (see
[AUDIO.md](AUDIO.md)).
