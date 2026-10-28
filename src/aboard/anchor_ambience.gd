class_name AnchorAmbience
extends Node2D
## Life at anchor, as seen aboard (revision 0.102b). While the boat is settled
## at anchor the whole boat scene takes on the time of day: a warm evening, a
## soft blue night, a pale morning (a CanvasModulate, eased in and out over a
## few seconds). Below deck, on evenings and nights, the cabin lamp casts a
## small warm glow. Underway, in harbour or when the anchor is not holding
## quietly, nothing changes: the scene looks exactly as before.
##
## Added by BoatArea; reads GameSession only.
##
## Iteration 17: the boat's lighting (BoatLighting) now shows the time of day
## everywhere (at anchor, underway and in harbour) with its own lamps, so this
## node no longer tints the scene or draws its glow (two CanvasModulates in one
## scene would fight). It still works out the settled-at-anchor mood (tint and
## lamp strength) for the anchor's moments and its tests.

const EASE_SECONDS := 2.5
const LAMP_COLOUR := Color(1.0, 0.85, 0.64)
## Rings of the soft glow (more rings: smoother falloff).
const RINGS := 18

## Set by BoatArea: the cabin lamps (local positions and radii), empty on deck.
var lamps: Array[Vector3] = []

var _tint := Color.WHITE
var _target := Color.WHITE
var _lamp_target := 0.0
var _lamp := 0.0
var _check_left := 0.0


func _ready() -> void:
	visible = false  # BoatLighting draws the light (Iteration 17)
	refresh(true)


func _process(delta: float) -> void:
	_check_left -= delta
	if _check_left <= 0.0:
		_check_left = 0.5
		refresh()
	var t := clampf(delta / EASE_SECONDS * 3.0, 0.0, 1.0)
	_tint = _tint.lerp(_target, t)
	var lamp := lerpf(_lamp, _lamp_target, t)
	if not is_equal_approx(lamp, _lamp):
		_lamp = lamp
		queue_redraw()


## Works out the look for now; `immediate` skips the easing (scene start).
func refresh(immediate := false) -> void:
	var phase := GameSession.get_day_phase() if GameSession.is_active() else AnchorLife.PHASE_DAY
	var settled := GameSession.is_settled_at_anchor()
	_target = AnchorLife.TINTS[phase] if settled else Color.WHITE
	_lamp_target = float(AnchorLife.LAMP[phase]) if settled and not lamps.is_empty() else 0.0
	if immediate:
		_tint = _target
		_lamp = _lamp_target
		queue_redraw()


func is_active() -> bool:
	return _target != Color.WHITE


func get_tint() -> Color:
	return _tint


func get_lamp_strength() -> float:
	return _lamp


func _draw() -> void:
	if _lamp <= 0.005:
		return
	for lamp in lamps:
		var centre := Vector2(lamp.x, lamp.y)
		# A soft radial glow: rings fading outwards.
		for i in RINGS:
			var f := 1.0 - float(i) / RINGS
			draw_circle(centre, lamp.z * (0.2 + 0.8 * float(i + 1) / RINGS),
				Color(LAMP_COLOUR, _lamp * 0.1 * f))
