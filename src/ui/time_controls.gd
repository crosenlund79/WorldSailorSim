class_name TimeControls
extends HBoxContainer
## Compact Pause / 1× / 5× / 20× selector, the one shared time-control bar
## (shown in the HUD on deck, in the cabin and on the chart). Reads and
## writes GameSession's pause state and time scale; the buttons never take
## keyboard focus so they do not interfere with movement or interaction keys.
##
## While paused, the Pause button is lit and no speed is; pressing Pause again
## resumes at the selected speed, and pressing a speed resumes at that speed.

var _buttons := {}
var _pause: Button


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	_pause = Button.new()
	_pause.name = "Pause"
	_pause.toggle_mode = true
	_pause.focus_mode = Control.FOCUS_NONE
	_pause.custom_minimum_size = Vector2(40, 0)
	_pause.theme_type_variation = &"MapButton"  # compact (Cozy Polish)
	_pause.icon = _pause_icon()
	_pause.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause.tooltip_text = "Pause: stop the clock (the boat and the wind wait). Press again, or pick a speed, to continue."
	_pause.toggled.connect(GameSession.set_paused)
	add_child(_pause)
	var group := ButtonGroup.new()
	for scale in SessionState.TIME_SCALES:
		var button := Button.new()
		button.name = "Speed%d" % scale
		button.text = "%d×" % scale
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(40, 0)
		button.theme_type_variation = &"MapButton"
		button.tooltip_text = ["Normal time", "Accelerated time", Loc.t("Fast time")][SessionState.TIME_SCALES.find(scale)]
		button.pressed.connect(GameSession.set_time_scale.bind(scale))
		add_child(button)
		_buttons[scale] = button
	GameSession.time_scale_changed.connect(_on_time_changed)
	GameSession.pause_changed.connect(_on_time_changed)
	GameSession.state_replaced.connect(_sync)
	GameSession.session_started.connect(_sync)
	_sync()


func _on_time_changed(_value: Variant) -> void:
	_sync()


func _sync() -> void:
	var paused := GameSession.is_paused()
	_pause.set_pressed_no_signal(paused)
	for scale: int in _buttons:
		(_buttons[scale] as Button).set_pressed_no_signal(not paused and scale == GameSession.get_time_scale())


## Two vertical bars in white (the universal pause symbol); the theme's
## icon colour tints them like the button text.
static func _pause_icon() -> ImageTexture:
	var image := Image.create(16, 18, false, Image.FORMAT_RGBA8)
	for y in 18:
		for x in 16:
			if x < 5 or x > 10:
				image.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(image)
