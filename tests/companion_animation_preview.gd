extends Node2D
## I024: every companion clip playing side by side, at game scale and
## enlarged - the reproducible evidence of the animation sets. One row per
## kind (cat, dog, parrot), one cell per clip; a clip that plays once starts
## again every two seconds. Open it in the editor (F6) or run it rendered:
##   xvfb-run godot --path . --rendering-driver opengl3 --resolution 1600x900 \
##     res://tests/companion_animation_preview.tscn -- --out=DIR
## With --out it saves a few moments of the grid (preview_<n>.png) and quits.

const CELL := Vector2(118, 150)
const SCALE := 1.7
const RESTART_S := 2.0

var _cells: Array[ShipCompanion] = []
var _clips: Array[StringName] = []
var _time := 0.0
var _out := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	var bg := ColorRect.new()
	bg.color = Color("#B9B4A6")  # cabin-sole tone
	bg.size = Vector2(1920, 1080)
	add_child(bg)
	var y := 30.0
	for kind in CompanionState.KINDS:
		var set := CompanionVisualSet.for_kind(kind)
		var x := 20.0
		for clip: StringName in set.get_pose_names():
			var label := Label.new()
			label.text = "%s · %s" % [kind, clip]
			label.position = Vector2(x, y)
			label.add_theme_color_override(&"font_color", Color("#20282C"))
			label.add_theme_font_size_override(&"font_size", 12)
			add_child(label)
			var pet := ShipCompanion.new()
			pet.preview = true
			pet.position = Vector2(x + CELL.x * 0.5, y + CELL.y * 0.62)
			pet.scale = Vector2(SCALE, SCALE)
			add_child(pet)
			pet.show_kind(kind)
			_cells.append(pet)
			_clips.append(clip)
			_start(pet, clip)
			x += CELL.x
			if x > 1600.0 - CELL.x:
				x = 20.0
				y += CELL.y
		y += CELL.y * 1.15
	if _out != "":
		_capture.call_deferred()


func _start(pet: ShipCompanion, clip: StringName) -> void:
	pet.pose = clip
	pet._pose_left = 1e9
	pet._play_clip(clip)
	pet._fade = 1.0
	if clip == CompanionVisualSet.POSE_FLY:
		pet._lift = ShipCompanion.FLY_HEIGHT * 0.6


func _process(delta: float) -> void:
	_time += delta
	if _time < RESTART_S:
		return
	_time = 0.0
	for i in _cells.size():
		var settings := _cells[i].visual_set.get_clip_settings(_clips[i])
		if not settings.loop:
			_start(_cells[i], _clips[i])


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	for n in 12:
		await get_tree().create_timer(0.15).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/preview_%d.png" % [_out, n])
	print("PREVIEW DONE")
	get_tree().quit()
