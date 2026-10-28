# Fish, sharks and junk (Iteration 18)

Original artwork made for Little Captain's Hat. It is painted by code, from
written descriptions of each species, with `tools/fishing/paint_fish.py`
(Python 3, Pillow, numpy). No photographs, clip art or other source images
were used. It falls under the same licence as the game's other original art.

The style (Real Horizon) is a gouache field-guide plate, like the ship's cat
and dog (`tools/companions/paint_companions.py`):
- countershading (dark back, silvery flank, pale belly), fine scales and a wet sheen;
- a thin translucent blue-grey edge line instead of ink; see-through fins with rays;
- small realistic eyes; a soft shadow.

## Layers

Each folder holds one catch, named by its id in `data/fishing/fishing.json`.
The layers share one 512 × 256 canvas, so they stack exactly.

| File | What | Used by |
|---|---|---|
| `body.png` | The fish without its tail, eye open | `FishPortrait` |
| `tail.png` | The tail alone, turned about its pivot to flick | `FishPortrait` |
| `lid.png` | The closed eye, shown for a moment to blink | `FishPortrait` |
| `art.png` | Junk only: the single picture (junk never blinks) | `FishPortrait` |
| `thumb.png` | 128 × 64 static picture | Cool box, trophy board, trophy plaques |

The tail pivot, the eye position and each catch's kind are written to
`data/fishing/fish_art.json` by the same script.

## Repainting

To repaint everything, or only the ids given:

    python3 tools/fishing/paint_fish.py [id ...]

After repainting, run `godot --headless --path . --import` so the editor and
the tests use the new textures.

To add a species: add it to `data/fishing/fishing.json` and give it a
description in `SPECIES` in the script. The description covers its outline,
fins, tail, colours, markings and eye. `test_fishing2` checks that every
species has art and that no two share a silhouette.
