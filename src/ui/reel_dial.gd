class_name ReelDial
extends Control
## The reel-in dial (Iteration 18): a ring with the target arc and, inside it,
## the smaller Perfect zone; a needle that goes round at a constant speed; the
## checks done and still needed (hooks along the bottom) and the grip left on
## the line (three knots). Clicking the dial is the same as the action key.
## Draws a ReelTiming; the menu steps it.
##
## Styled as a marine instrument (Real Horizon): a dark face with fine ticks,
## the target arc in success green and its Perfect zone in muted gold (the
## fishing hint calls it "the gold middle"), a white pointer, cyan for checks
## done; amber only for a miss and a lost grip.

signal pressed

const Instrument := preload("res://src/ui/instrument_draw.gd")
const FLASH_SECONDS := 0.3

var timing: TimingCheck
var _flash := 0.0
var _flash_colour := Color.TRANSPARENT


func _ready() -> void:
	custom_minimum_size = Vector2(280, 330)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = Loc.t("Click (or press E / Space) when the needle is in the green arc.")


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
		accept_event()


## A short ring flash for a press's outcome (gentle with Reduce flashing).
func flash(outcome: StringName) -> void:
	match outcome:
		ReelTiming.PRESS_PERFECT:
			_flash_colour = UiTheme.color(&"caution")
		ReelTiming.PRESS_HIT:
			_flash_colour = UiTheme.color(&"success")
		ReelTiming.PRESS_MISS:
			_flash_colour = UiTheme.color(&"warning")
		_:
			return
	_flash = FLASH_SECONDS


func _process(delta: float) -> void:
	_flash = maxf(_flash - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	if timing == null:
		return
	var radius := minf(size.x, size.y - 70.0) / 2.0 - 12.0
	var center := Vector2(size.x / 2.0, radius + 12.0)
	var width := 16.0
	var ink := UiTheme.color(&"ink")
	var soft := UiTheme.color(&"ink_soft")
	# The face: dark glass, a hairline bezel, the track and fine ticks.
	Instrument.face(self, center, radius + width / 2.0 + 6.0)
	draw_arc(center, radius, 0.0, TAU, 96, UiTheme.color(&"track"), width, true)
	Instrument.ticks(self, center, radius - width / 2.0 - 3.0, 0.0, 360.0, 10.0, 3, 4.0, 9.0)
	# The target arc and its Perfect zone (angles: 0 = top, clockwise).
	var half := timing.arc_deg / 2.0
	Instrument.arc(self, center, radius, timing.target_deg - half, timing.target_deg + half, Color(UiTheme.color(&"success"), 0.85), width)
	var perfect_half := timing.get_perfect_deg() / 2.0
	Instrument.arc(self, center, radius, timing.target_deg - perfect_half, timing.target_deg + perfect_half, UiTheme.color(&"caution"), width - 6.0)
	# Hairline edges of the target, like limit marks on a gauge.
	for edge in [timing.target_deg - half, timing.target_deg + half]:
		var d := Instrument.dir(edge)
		draw_line(center + d * (radius - width / 2.0), center + d * (radius + width / 2.0 + 4.0), ink, 1.5, true)
	# The outcome flash around the ring.
	if _flash > 0.0:
		var strength := _flash / FLASH_SECONDS * (0.45 if SettingsManager.get_reduce_flashing() else 0.9)
		draw_arc(center, radius + width / 2.0 + 10.0, 0.0, TAU, 96, Color(_flash_colour, strength), 3.0, true)
	# The pointer.
	Instrument.pointer(self, center, timing.angle, radius + width / 2.0, UiTheme.color(&"title"), 3.0)
	# Checks along the bottom (segments, filled cyan when done), and the
	# line's grip (three marks, amber crossed when lost).
	var base_y := center.y + radius + width / 2.0 + 30.0
	var n := timing.checks_needed
	for i in n:
		var x := size.x / 2.0 + (i - (n - 1) / 2.0) * 34.0
		var done := i < timing.hits
		var cell := Rect2(Vector2(x - 12, base_y - 9), Vector2(24, 18))
		draw_rect(cell, UiTheme.color(&"accent") if done else UiTheme.color(&"surface_sunken"))
		draw_rect(cell, UiTheme.color(&"accent") if done else UiTheme.color(&"border"), false, 1.0)
		if done:
			var dark := UiTheme.color(&"action_text")
			draw_line(Vector2(x - 5, base_y), Vector2(x - 1, base_y + 4), dark, 2.0, true)
			draw_line(Vector2(x - 1, base_y + 4), Vector2(x + 6, base_y - 4), dark, 2.0, true)
	for i in timing.line_control:
		var x := size.x / 2.0 + (i - (timing.line_control - 1) / 2.0) * 26.0
		var left := i < timing.get_line_control()
		var knot := Vector2(x, base_y + 32.0)
		draw_line(knot - Vector2(11, 0), knot + Vector2(11, 0), Color(soft, 0.6), 1.0, true)
		draw_circle(knot, 5.0, ink if left else UiTheme.color(&"surface_sunken"))
		draw_arc(knot, 5.0, 0.0, TAU, 16, ink if left else Color(soft, 0.6), 1.0, true)
		if not left:
			var amber := UiTheme.color(&"warning")
			draw_line(knot + Vector2(-5, -5), knot + Vector2(5, 5), amber, 2.0, true)
			draw_line(knot + Vector2(-5, 5), knot + Vector2(5, -5), amber, 2.0, true)
