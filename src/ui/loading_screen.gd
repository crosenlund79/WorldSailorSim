class_name LoadingScreen
extends CanvasLayer
## The game's own start (Cozy Polish): after Godot's boot splash (an image
## the engine shows while it starts; nothing of the game can draw then), this
## screen shows the logo over the title illustration (Real Horizon: an
## overcast sea, a lighthouse, a sloop under sail) - always the main menu's
## own picture (I022: it does not follow the time of day, so the start looks
## like the menu it fades into) -
## while the game loads what it needs, naming each real step as it runs.
## The heaviest step (the routing charts) runs on a worker thread, so the
## screen keeps moving. It fades into the main menu as soon as the loading
## is done; there is no artificial wait. Purely visual: clicks and keys reach
## the menu under it. Shown once per launch, and not without a display.

signal finished

const FADE_SECONDS := 0.45
const LOGO := preload("res://assets/branding/png/little_captains_hat_logo_480.png")
## The main menu's own background (src/ui/main_menu.tscn, Background).
const TITLE := preload("res://assets/ui/title_scene.png")

## Shown already in this run of the game.
static var shown := false

var _steps: Array[Dictionary] = []
var _step := -1
var _task := -1
var _done := false
var _time := 0.0
var _status: Label
var _canvas: Control
var _night := false


## True when there is a screen to show it on and it has not been shown yet.
static func wanted() -> bool:
	return not shown and DisplayServer.get_name() != "headless"


func _ready() -> void:
	shown = true
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_night = true  # the main menu's night look, whatever the hour
	_canvas = Control.new()
	_canvas.name = "Canvas"
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_scene)
	add_child(_canvas)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override(&"separation", 10)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.position.y -= 80.0
	_canvas.add_child(column)
	var logo := TextureRect.new()
	logo.texture = LOGO  # the white wordmark, as on the menu
	logo.custom_minimum_size = Vector2(440, 206)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(logo)
	var tagline := Label.new()
	tagline.text = "Small boat. Wide world. Hold onto your hat."
	tagline.theme_type_variation = &"DisplayTagline"
	tagline.add_theme_color_override(&"font_color", UiTheme.color_at(&"ink_soft", 1.0))
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(tagline)
	_status = Label.new()
	_status.name = "Status"
	_status.theme_type_variation = &"MutedLabel"
	_status.add_theme_color_override(&"font_color", Color(UiTheme.color_at(&"ink_soft", 1.0), 0.8))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.custom_minimum_size = Vector2(520, 0)
	column.add_child(_status)
	# The real work, in order. Each is what the game would otherwise do the
	# first time it needs it.
	_steps = [
		{"text": Loc.t("Reading the harbour list…"), "work": func() -> void: PortCatalog.get_default()},
		{"text": Loc.t("Unrolling the charts of the world…"), "thread": func() -> void: SeaRouter.get_default()},
		{"text": Loc.t("Making the cabin ready…"), "work": func() -> void: VesselCatalog.get_default()},
	]
	_next_step()


func _next_step() -> void:
	_step += 1
	if _step >= _steps.size():
		_finish()
		return
	var step: Dictionary = _steps[_step]
	_status.text = Loc.t("%s  (%d of %d)") % [step.text, _step + 1, _steps.size()]
	if step.has("thread"):
		_task = WorkerThreadPool.add_task(step.thread, false, Loc.t("Loading: %s") % step.text)
	else:
		# Quick steps run on the next frame, after the text is shown.
		(func() -> void:
			(step.work as Callable).call()
			_next_step()).call_deferred()


func _process(delta: float) -> void:
	_time += delta
	_canvas.queue_redraw()
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_next_step()


func _finish() -> void:
	if _done:
		return
	_done = true
	_status.text = "Ready. Welcome aboard."
	var tween := create_tween()
	tween.tween_property(_canvas, "modulate:a", 0.0, FADE_SECONDS)
	tween.tween_callback(func() -> void:
		finished.emit()
		queue_free())


func is_done() -> bool:
	return _done


## The scene behind the logo: the title illustration (an overcast sea, a
## headland with its lighthouse, a sloop under sail), drifting very slowly, with a soft breathing light over the sea.
func _draw_scene() -> void:
	var size := _canvas.size
	var picture: Texture2D = TITLE
	var scale := maxf(size.x / picture.get_width(), size.y / picture.get_height()) * 1.04
	var drawn := picture.get_size() * scale
	var drift := Vector2(sin(_time * 0.07) * 0.5 - 0.5, 0.0) * (drawn.x - size.x) * 0.5
	_canvas.draw_texture_rect(picture, Rect2((size - drawn) / 2.0 + drift, drawn), false)
	_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(UiTheme.color_at(&"surface", 1.0), 0.25 + 0.04 * sin(_time * 0.6)))
