class_name Player
extends CharacterBody2D
## The player on board, drawn as a little sailor (SailorDrawing): keyboard
## movement with collision, plus an InteractionSensor for nearby objects. It reads input only while the game is
## unpaused, so open menus automatically block movement and interaction.

signal focus_changed(interactable: Interactable)

@export var speed := 250.0

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
	velocity = direction * speed
	var before := position
	move_and_slide()
	if direction != Vector2.ZERO and not direction.is_equal_approx(_facing):
		_facing = direction.normalized()
		queue_redraw()
	_animate_walk(position.distance_to(before), _delta)


## Arm swing (presentation only): one stride per STRIDE units walked, easing
## to rest when stopped. Never affects movement or collision.
const STRIDE := 46.0


func _animate_walk(moved: float, delta: float) -> void:
	var target := 1.0 if moved > 0.5 else 0.0
	var amount := move_toward(_walk_amount, target, delta * 6.0)
	if moved > 0.0:
		_walk_phase = fmod(_walk_phase + moved / STRIDE * PI, TAU)
	if amount != _walk_amount or moved > 0.0:
		_walk_amount = amount
		queue_redraw()


## The walking cycle now (-1..1, 0 when standing).
func get_swing() -> float:
	return sin(_walk_phase) * _walk_amount


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
		cafe_mug or (GameSession.is_active() and GameSession.is_carrying_coffee()))
