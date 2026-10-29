class_name Player
extends CharacterBody2D
## The player on board, drawn as a little sailor (SailorDrawing): keyboard
## movement with collision, plus an InteractionSensor for nearby objects. It reads input only while the game is
## unpaused, so open menus automatically block movement and interaction.

signal focus_changed(interactable: Interactable)
## An automatic walk (walk_along) ended: arrived, or stopped (a movement key,
## or the way stayed blocked).
signal auto_walk_finished(arrived: bool)

@export var speed := 250.0
## Holding the run key (Shift; I027 playtest) the Captain runs this much
## faster - no stamina, walking stays the default. The walk cycle follows the
## distance covered, so the steps quicken with the speed.
const RUN_FACTOR := 1.75
## A running stride is longer than a walking one (× the walk's step), so the
## cadence rises less than the speed, as it does for a person.
const RUN_STRIDE := 1.3
var _running := false

## Collision radius (the CollisionShape2D in player.tscn is 20); the drawing
## (SailorDrawing) stays within about this size.
const RADIUS := 21.0

var input_enabled := true
## The view's rotation (the deck camera's, Iteration 12): the movement keys
## move the sailor up, down, left and right on screen whatever way the deck
## is turned.
var view_rotation := 0.0
var _facing := Vector2.RIGHT
## Walking cycle (radians), advanced by the distance actually walked, so the
## arms swing with the steps and rest when the player stands still.
var _walk_phase := 0.0
var _walk_amount := 0.0
## True once the movement keys have been let go since the Captain appeared in
## this place (I027 playtest): the walkway's passages only take a Captain who
## walks into them, never one still holding the key that brought them here.
var keys_released := false
## The automatic walk (I027 playtest, the quay's action wheel): the points
## still to reach, and how long the Captain has made no headway.
var _auto_path := PackedVector2Array()
var _auto_stuck := 0.0
## An automatic walk gives up after this long without headway (s).
const AUTO_STUCK_SECONDS := 1.2
## A café's mug in hand (I026, the quay's café): drawn like the boat's own
## mug, but it is the café's - nothing in the game state changes.
var cafe_mug := false:
	set(value):
		cafe_mug = value
		queue_redraw()

@onready var _sensor: InteractionSensor = $InteractionSensor


func _ready() -> void:
	add_to_group(&"player")
	_sensor.focus_changed.connect(focus_changed.emit)
	# The captain's hat is drawn by its own art-only child (no collision).
	var hat := PlayerHat.new()
	hat.name = "PlayerHat"
	add_child(hat)
	# The mug in hand (Cozy Polish) shows and goes with the coffee's place.
	GameSession.coffee_changed.connect(_on_coffee_changed)
	GameSession.state_replaced.connect(queue_redraw)


func _on_coffee_changed(_place: StringName) -> void:
	queue_redraw()


func get_hat_visual() -> PlayerHat:
	return get_node_or_null(^"PlayerHat") as PlayerHat


func _physics_process(_delta: float) -> void:
	var direction := Vector2.ZERO
	if input_enabled:
		# get_vector() limits the length to 1, so diagonals are not faster.
		direction = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down").rotated(view_rotation)
	if direction != Vector2.ZERO and not _auto_path.is_empty():
		stop_auto_walk()  # a movement key takes over
	elif direction == Vector2.ZERO and not _auto_path.is_empty() and input_enabled:
		direction = _auto_direction()
	_running = input_enabled and Input.is_action_pressed(&"run") and _auto_path.is_empty() and direction != Vector2.ZERO
	velocity = direction * speed * (RUN_FACTOR if _running else 1.0)
	if not keys_released and Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down") == Vector2.ZERO:
		keys_released = true  # the keys themselves, whether or not input is enabled yet
	var before := position
	move_and_slide()
	if direction != Vector2.ZERO and not direction.is_equal_approx(_facing):
		_facing = direction.normalized()
		queue_redraw()
	_animate_walk(position.distance_to(before), _delta)
	if not _auto_path.is_empty():
		_auto_stuck = _auto_stuck + _delta if position.distance_to(before) < speed * _delta * 0.25 else 0.0
		if _auto_stuck > AUTO_STUCK_SECONDS:
			_auto_path.clear()
			auto_walk_finished.emit(false)


## Walks the Captain along `points` by itself (the movement keys stop it at
## any time); auto_walk_finished tells how it ended.
func walk_along(points: PackedVector2Array) -> void:
	_auto_path = points.duplicate()
	_auto_stuck = 0.0


func stop_auto_walk() -> void:
	if _auto_path.is_empty():
		return
	_auto_path.clear()
	auto_walk_finished.emit(false)


func is_auto_walking() -> bool:
	return not _auto_path.is_empty()


## Towards the next point (dropping the points already reached).
func _auto_direction() -> Vector2:
	while not _auto_path.is_empty() and position.distance_to(_auto_path[0]) < 6.0:
		_auto_path.remove_at(0)
	if _auto_path.is_empty():
		auto_walk_finished.emit(true)
		return Vector2.ZERO
	return position.direction_to(_auto_path[0])


## The walk (presentation only): HumanGait's cycle advances with the distance
## walked (I027: its adult step, so the cadence matches the speed and the feet
## stay planted), easing to rest when stopped. Never affects movement or
## collision.
func _animate_walk(moved: float, delta: float) -> void:
	var amount := HumanGait.ease_amount(_walk_amount, moved > 0.5, delta)
	if moved > 0.0:
		_walk_phase = HumanGait.advance(_walk_phase, moved, HumanGait.STEP * (RUN_STRIDE if _running else 1.0))
	if amount != _walk_amount or moved > 0.0:
		_walk_amount = amount
		queue_redraw()


## The arms' swing now (-1..1, 0 when standing).
func get_swing() -> float:
	return HumanGait.swing(_walk_phase, _walk_amount)


## The walking cycle: [phase, amount] (HumanGait).
func get_gait() -> Vector2:
	return Vector2(_walk_phase, _walk_amount)


## Where the player's left hand is (a carried hat is held there).
func get_carry_point() -> Vector2:
	return SailorDrawing.hand_position(_facing, 0.2, -1.0)


func _unhandled_input(event: InputEvent) -> void:
	if input_enabled and event.is_action_pressed(&"interact") and not event.is_echo():
		if _sensor.interact(self):
			get_viewport().set_input_as_handled()


## The direction the player faces (unit vector; the last direction moved).
func get_facing() -> Vector2:
	return _facing


## Turns the player to face `direction` (used when placing the player).
func set_facing(direction: Vector2) -> void:
	if direction != Vector2.ZERO:
		_facing = direction.normalized()
		queue_redraw()


func get_focused_interactable() -> Interactable:
	return _sensor.focused


func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	if not enabled:
		velocity = Vector2.ZERO
		_sensor.clear_focus()


func _draw() -> void:
	var hat := get_hat_visual()
	SailorDrawing.draw(self, _facing, get_swing(), hat != null and hat.get_shown_status() == HatState.CARRIED,
		cafe_mug or (GameSession.is_active() and GameSession.is_carrying_coffee()), _walk_phase, _walk_amount)
