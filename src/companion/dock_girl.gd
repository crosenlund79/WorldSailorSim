class_name DockGirl
extends Node2D
## The little girl on the pontoon (I025, DockEncounterScene): walks in, stops,
## waves, picks up the box and walks away again. Drawn by GirlDrawing. Not a
## full NPC: no interaction, no dialogue, no state of her own beyond this
## moment, and nothing is saved.

## A child's unhurried walk (the Captain walks faster).
const SPEED := 46.0
## Steps per second at that speed (the arms' swing).
const STEP_RATE := 1.6

var facing := Vector2.RIGHT
var waving := 0.0
var carrying_box := false
var _target := Vector2.ZERO
var _walking := false
var _phase := 0.0
var _wave_left := 0.0


func _ready() -> void:
	z_index = 5


func walk_to(target: Vector2) -> void:
	_target = target
	_walking = position.distance_to(target) > 1.0
	if _walking:
		facing = (target - position).normalized()


func is_walking() -> bool:
	return _walking


## Raises a hand for `seconds` (a greeting).
func wave(seconds: float) -> void:
	_wave_left = seconds


func face(direction: Vector2) -> void:
	if direction.length() > 0.5:
		facing = direction.normalized()


## Her left shoulder in the parent's coordinates (where a bird perches).
func get_shoulder() -> Vector2:
	return position + GirlDrawing.shoulder_point(facing)


func _process(delta: float) -> void:
	if _walking:
		var step := SPEED * delta
		var to := _target - position
		if to.length() <= step:
			position = _target
			_walking = false
		else:
			position += to.normalized() * step
			facing = to.normalized()
		_phase += delta * STEP_RATE * TAU
	_wave_left = maxf(_wave_left - delta, 0.0)
	var wave_goal := 1.0 if _wave_left > 0.0 else 0.0
	waving = move_toward(waving, wave_goal, delta * 4.0)
	queue_redraw()


func _draw() -> void:
	var swing := sin(_phase) if _walking else 0.0
	# A raised hand moves a little from side to side.
	var wave := waving * (0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.012))
	GirlDrawing.draw(self, facing, swing, wave, carrying_box)
