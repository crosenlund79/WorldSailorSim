class_name CompanionPoseArt
extends Resource
## One pose of a companion: which image to show for it and small presentation
## adjustments. Part of a CompanionVisualSet; see
## DEV_GUIDES/COMPANION_ANIMATION.md.

## Logical pose name, e.g. &"resting", &"sleeping", &"alert", &"stretching".
@export var pose: StringName
## The image (PNG). Kept as a path so a missing file never stops the set from
## loading: the pose then falls back (see CompanionVisualSet).
@export_file("*.png") var image_path := ""
## Shift in scene units (+x right, +y down) when this pose's drawing is not
## centred like the others on the shared canvas.
@export var offset := Vector2.ZERO
## Size multiplier for this pose only (1 = same logical size as the others).
@export_range(0.25, 4.0, 0.01) var scale := 1.0
## Mirror the image horizontally.
@export var flip_h := false

@export_group("Animation")
## The clip's frames after the first (image_path is frame 0). Empty: a still
## pose, as before. A Sprite Workshop replacement of the pose replaces the
## whole clip with its single image (the Captain's drawing wins).
@export_file("*.png") var frames: Array[String] = []
## Frames per second while the clip plays.
@export_range(0.5, 30.0, 0.5) var fps := 8.0
## Loops (idle, walk, sleep) or plays once and holds its last frame
## (lie down, wake, takeoff, landing, ...).
@export var loop := true


## Every frame path of the clip, frame 0 first.
func get_frame_paths() -> Array[String]:
	var paths: Array[String] = [image_path]
	paths.append_array(frames)
	return paths
