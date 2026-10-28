class_name HatBadge
extends PanelContainer
## A small, quiet hat indicator in the HUD (Iteration 12), so the hat's fate
## never depends on hearing it:
##   - at risk: the hat is worn on deck after the wind warning; the little hat
##     flutters and the badge says "Hold onto your hat!  H";
##   - missing: the hat is lost; a faded hat with a question mark says
##     "Hat missing" until a replacement is bought;
##   - otherwise the badge is hidden.
## It only reads GameSession (presentation only, nothing is saved).

const STATE_NONE := &"none"
const STATE_AT_RISK := &"at_risk"
const STATE_MISSING := &"missing"

const AT_RISK_TEXT := "Hold onto your hat!"
const MISSING_TEXT := "Hat missing"
## How long the hat's notifications stay up (longer than ordinary notices).
const WARNING_SECONDS := 7.0
const LOST_SECONDS := 9.0
const LOST_HEADLINE := "Hat overboard!"
const MISSING_TIP := "Your captain's hat blew away. The harbour grocery store sells a new one."

var _state: StringName = STATE_NONE
var _icon: Control
var _label: Label
var _key: Label
var _time := 0.0
## Seconds of extra attention (a gentle pulse) after the hat was just lost.
var _pulse := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_type_variation = &"HudPanel"
	var box := HBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_icon = Control.new()
	_icon.custom_minimum_size = Vector2(40, 34)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.draw.connect(_draw_icon)
	box.add_child(_icon)
	_label = Label.new()
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(_label)
	_key = Label.new()
	_key.theme_type_variation = &"KeyLabel"
	_key.text = "H"
	_key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(_key)
	hide()


func _process(delta: float) -> void:
	_time += delta
	_pulse = maxf(_pulse - delta, 0.0)
	refresh()
	visible = _state != STATE_NONE
	if visible:
		_icon.queue_redraw()
		modulate = Color(1.0, 1.0, 1.0, 1.0) if _pulse <= 0.0 else Color(1.0, 0.85 + 0.15 * cos(_time * 9.0), 0.75 + 0.25 * cos(_time * 9.0))


## Works the state out from the game (also called by the HUD and tests).
func refresh() -> void:
	set_state(state_for_game())


static func state_for_game() -> StringName:
	if not GameSession.is_active():
		return STATE_NONE
	if GameSession.get_hat_status() == HatState.LOST:
		return STATE_MISSING
	return STATE_AT_RISK if GameSession.is_hat_at_risk() else STATE_NONE


func set_state(state: StringName) -> void:
	if state == _state:
		return
	_state = state
	visible = state != STATE_NONE
	_label.text = AT_RISK_TEXT if state == STATE_AT_RISK else MISSING_TEXT
	UiTheme.tint(_label, &"caution" if state == STATE_AT_RISK else &"")
	_key.visible = state == STATE_AT_RISK
	tooltip_text = MISSING_TIP if state == STATE_MISSING else Loc.t("Press H to take your hat off, or go below.")


func get_state() -> StringName:
	return _state


func get_text() -> String:
	return _label.text if visible else ""


## A few seconds of gentle pulsing to draw the eye (the hat was just lost).
func pulse(seconds := 6.0) -> void:
	_pulse = seconds


func _draw_icon() -> void:
	var center := _icon.size * 0.5
	if _state == STATE_AT_RISK:
		# The hat flutters: a quick wobble and a little lift, with wind lines.
		var wobble := sin(_time * 11.0) * 0.28 + sin(_time * 5.3) * 0.12
		var lift := absf(sin(_time * 5.5)) * 3.0
		HatArt.get_default().draw_slot(_icon, HatArt.SLOT_WORN, center + Vector2(2, -lift), -PI / 2 + wobble, 1.0, 1.15)
		for i in 3:
			var y := center.y - 8.0 + i * 8.0
			var x0 := 2.0 + fmod(_time * 30.0 + i * 9.0, 10.0)
			_icon.draw_line(Vector2(x0 - 6, y), Vector2(x0, y), Color(UiTheme.color(&"ink_soft"), 0.8), 1.0, true)
	elif _state == STATE_MISSING:
		HatArt.get_default().draw_slot(_icon, HatArt.SLOT_WORN, center, -PI / 2, 0.35, 1.15)
		var font := get_theme_default_font()
		_icon.draw_string(font, center + Vector2(-5, 8), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UiTheme.color(&"warning"))
