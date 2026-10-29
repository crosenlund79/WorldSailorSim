class_name PlayerHat
extends Node2D
## The captain's hat on the player token: worn on the head (turned the way
## the player faces) or, when taken off, tucked under the arm. Art only, with
## no collision: the player's shape and movement are unchanged. It follows
## GameSession's hat state.

## Where a carried hat is drawn (beside the token, on its left), and its
## scale against the stored slot's size: the same size as when worn (I027;
## it was about twice that).
const CARRIED_OFFSET := Vector2(-6, -22)
const CARRIED_SCALE := 0.28

var _status: StringName = &""
var _facing := Vector2.RIGHT


func _ready() -> void:
	GameSession.hat_changed.connect(func(_status: StringName) -> void: refresh())
	GameSession.state_replaced.connect(refresh)
	refresh()


func refresh() -> void:
	_status = GameSession.get_hat_status() if GameSession.is_active() else HatState.STORED
	visible = _status == HatState.WORN or _status == HatState.CARRIED
	queue_redraw()
	var player := get_parent() as CanvasItem
	if player:
		player.queue_redraw()  # the arm holding a carried hat


## What is shown: HatState.WORN, CARRIED, or anything else for nothing.
func get_shown_status() -> StringName:
	return _status if visible else &""


func _process(_delta: float) -> void:
	var player := get_parent()
	if visible and player and player.has_method(&"get_facing"):
		var facing: Vector2 = player.get_facing()
		if not facing.is_equal_approx(_facing):
			_facing = facing
			queue_redraw()


func _draw() -> void:
	var art := HatArt.get_default()
	if _status == HatState.WORN:
		art.draw_slot(self, HatArt.SLOT_WORN, Vector2.ZERO, _facing.angle())
	elif _status == HatState.CARRIED:
		var player := get_parent()
		var hand: Vector2 = player.get_carry_point() if player and player.has_method(&"get_carry_point") else CARRIED_OFFSET.rotated(_facing.angle())
		art.draw_slot(self, HatArt.SLOT_STORED, hand + _facing.orthogonal() * -4.0, _facing.angle() + PI * 0.5, 1.0, CARRIED_SCALE)
