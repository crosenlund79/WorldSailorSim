class_name SailTrimPanel
extends SimplePanel
## Sail trim (Iteration 18): ease or sheet in the sails by hand, or leave it
## to the crew. A slider from Eased to Sheeted in; the sketch shows the boat
## from above with the wind, the boom where the captain has it and, faintly,
## where it would draw best; a plain word says how it is ("Too loose", "Well
## trimmed", "Too tight") and what it does to the speed (a few percent).
## A/D or the arrow keys ease and sheet in; Space hands it to the crew;
## T or Esc closes. Changes apply at once (GameSession.set_sail_trim).

const STEP := 0.05
const Instrument := preload("res://src/ui/instrument_draw.gd")

var _slider: HSlider
var _auto: CheckBox
var _wind: Label
var _feedback: Label
var _sketch: Control


func _ready() -> void:
	_build("Sail trim", 560.0)
	_wind = _label("Wind", "", &"MutedLabel")
	_sketch = Control.new()
	_sketch.name = "Sketch"
	_sketch.custom_minimum_size = Vector2(520, 200)
	_sketch.draw.connect(_draw_sketch)
	_box.add_child(_sketch)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	_box.add_child(row)
	var eased := Label.new()
	eased.text = "Eased"
	row.add_child(eased)
	_slider = HSlider.new()
	_slider.name = "Trim"
	_slider.min_value = -1.0
	_slider.max_value = 1.0
	_slider.step = STEP
	_slider.custom_minimum_size = Vector2(340, 32)
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.focus_mode = Control.FOCUS_NONE
	_slider.value_changed.connect(func(value: float) -> void: set_trim(value))
	row.add_child(_slider)
	var tight := Label.new()
	tight.text = "Sheeted in"
	row.add_child(tight)
	_feedback = _label("Feedback", "", &"HeaderLabel")
	_auto = CheckBox.new()
	_auto.name = "Auto"
	_auto.text = "Leave it to the crew"
	_auto.tooltip_text = "The crew keeps the sails sensibly trimmed: the boat sails as it always has. Trim by hand to sail a little faster (or slower)."
	_auto.focus_mode = Control.FOCUS_NONE
	_auto.toggled.connect(func(on: bool) -> void:
		GameSession.set_sail_trim(on, GameSession.get_sail_trim().value)
		refresh())
	_box.add_child(_auto)
	_label("Hint", "A / D or arrows: ease or sheet in  ·  Space: leave it to the crew  ·  T or Esc: close", &"MutedLabel")
	_button("CloseButton", "Close", close)
	GameSession.sail_trim_changed.connect(refresh)
	UiTheme.palette_changed.connect(_sketch.queue_redraw)
	GameSession.propulsion_changed.connect(func(_mode: StringName) -> void: refresh())
	refresh()


## Sets the captain's own trim (and takes it from the crew).
func set_trim(value: float) -> void:
	GameSession.set_sail_trim(false, value)


func refresh() -> void:
	if not is_inside_tree():
		return
	var trim := GameSession.get_sail_trim()
	var propulsion := GameSession.get_propulsion()
	_slider.set_value_no_signal(float(trim.value))
	_auto.set_pressed_no_signal(bool(trim.auto))
	var angle := propulsion.true_wind_angle
	_wind.text = Loc.t("Wind %d kn, %d° on the %s (%s)") % [roundi(propulsion.wind_speed_kn), roundi(absf(angle)),
		PropulsionState.wind_side(angle), PropulsionState.point_of_sail_name(angle).to_lower()]
	if propulsion.is_motoring():
		_feedback.text = "Under engine: the sails are not drawing."
	else:
		var word := SailTrim.feedback(trim.auto, trim.value, angle, propulsion.wind_speed_kn)
		var pct := SailTrim.percent(trim.auto, trim.value, angle, propulsion.wind_speed_kn)
		_feedback.text = word if trim.auto else Loc.t("%s  ·  speed %+d %%") % [word, pct]
	_sketch.queue_redraw()


func get_feedback_text() -> String:
	return _feedback.text


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"move_left") or event.is_action_pressed(&"ui_left"):
		set_trim(GameSession.get_sail_trim().value - STEP)
	elif event.is_action_pressed(&"move_right") or event.is_action_pressed(&"ui_right"):
		set_trim(GameSession.get_sail_trim().value + STEP)
	elif event.is_action_pressed(&"ui_accept") and not event.is_echo():
		GameSession.set_sail_trim(true, GameSession.get_sail_trim().value)
	elif event.is_action_pressed(&"sail_trim") and not event.is_echo():
		close()
	else:
		return
	get_viewport().set_input_as_handled()


func _draw_sketch() -> void:
	var propulsion := GameSession.get_propulsion()
	var trim := GameSession.get_sail_trim()
	var center := _sketch.size / 2.0 + Vector2(0, 6)
	# Instrument colours (Real Horizon): white figures on dark glass.
	var ink := UiTheme.color(&"ink")
	var wind_colour := UiTheme.color(&"ink_soft")
	# A wind-angle dial round the boat: fine ticks every 10°, longer every 30°,
	# and the no-go zone either side of the bow as a faint amber limit.
	var dial_r := 92.0
	_sketch.draw_arc(center, dial_r, 0.0, TAU, 96, UiTheme.color(&"border_soft"), 1.0, true)
	Instrument.ticks(_sketch, center, dial_r, 0.0, 360.0, 10.0, 3, 3.0, 7.0)
	Instrument.arc(_sketch, center, dial_r + 3.0, -40.0, 40.0, Color(UiTheme.color(&"warning"), 0.5), 2.0)
	# The boat from above, bow up: a plan-view outline on sunken glass.
	var hull := PackedVector2Array([center + Vector2(0, -78), center + Vector2(26, -30), center + Vector2(24, 50),
		center + Vector2(14, 72), center + Vector2(-14, 72), center + Vector2(-24, 50), center + Vector2(-26, -30)])
	_sketch.draw_colored_polygon(hull, UiTheme.color(&"surface_sunken"))
	Instrument.outline(_sketch, hull, ink, 1.5)
	_sketch.draw_line(center + Vector2(0, -70), center + Vector2(0, 64), Color(ink, 0.18), 1.0)
	var mast := center + Vector2(0, -24)
	# The wind (an arrow toward the boat from where it comes).
	var a := deg_to_rad(propulsion.true_wind_angle)
	var from := Vector2(sin(a), -cos(a))
	var tail := center + from * 150.0
	var head := center + from * 96.0
	_sketch.draw_line(tail, head, wind_colour, 2.0, true)
	var side := (head - tail).normalized().orthogonal() * 7.0
	_sketch.draw_colored_polygon(PackedVector2Array([head + (head - tail).normalized() * 12.0, head + side, head - side]), wind_colour)
	_sketch.draw_string(get_theme_default_font(), tail + Vector2(-20, -10), "wind", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, wind_colour)
	if propulsion.is_motoring():
		_sketch.draw_circle(mast, 5.0, ink)
		return
	# The boom on the side away from the wind: sheeted in = along the boat.
	var leeward := -1.0 if propulsion.true_wind_angle > 0.0 else 1.0
	var best := SailTrim.best(propulsion.true_wind_angle, propulsion.wind_speed_kn)
	for pair in [[best, Color(ink, 0.3), 2.0], [float(trim.value) if not trim.auto else best, UiTheme.color(&"accent"), 4.0]]:
		var swing := deg_to_rad(lerpf(8.0, 80.0, (1.0 - float(pair[0])) / 2.0)) * leeward
		var end: Vector2 = mast + Vector2(sin(swing), cos(swing)) * 88.0
		_sketch.draw_line(mast, end, pair[1], pair[2], true)
	_sketch.draw_circle(mast, 4.0, UiTheme.color(&"surface_raised"))
	_sketch.draw_arc(mast, 4.0, 0.0, TAU, 16, ink, 1.5, true)
