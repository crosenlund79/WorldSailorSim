class_name CoffeeMug
extends Node2D
## The captain's coffee mug where it stands (Cozy Polish): in the cup holder
## by the helm on deck (the holder is always there, the mug when it is in it),
## or on the cabin table. Drawn from above in the game's hand-drawn style;
## presentation only, it follows GameSession.get_coffee().

## "holder" (deck, with its bracket) or "table" (cabin).
var place: StringName = &"holder"

const RIM := Color("#2A3236")
const MUG := Color("#E3E4DE")
const MUG_SHADE := Color("#B8BBB5")
const COFFEE := Color("#5a3a24")
const COFFEE_SHINE := Color("#8a5d3c")
const BRASS := Color("#8E989B")
const BRASS_DARK := Color("#545E62")


func _ready() -> void:
	GameSession.coffee_changed.connect(_on_coffee_changed)
	GameSession.state_replaced.connect(queue_redraw)


func _on_coffee_changed(_place: StringName) -> void:
	queue_redraw()


func has_mug() -> bool:
	return GameSession.get_coffee() == place


func _draw() -> void:
	if place == &"holder":
		# A small brass ring on a bracket against the coaming.
		draw_rect(Rect2(-4, 6, 8, 10), BRASS_DARK)
		draw_circle(Vector2.ZERO, 10.5, BRASS_DARK)
		draw_circle(Vector2.ZERO, 8.5, BRASS)
		draw_circle(Vector2.ZERO, 6.0, Color(0.12, 0.1, 0.08, 0.55))
	if has_mug():
		draw_mug(self, Vector2.ZERO, 1.0)


## A mug from above: rim, a little handle, coffee with a shine.
static func draw_mug(canvas: CanvasItem, at: Vector2, scale: float, angle := 0.0) -> void:
	var handle := at + Vector2.from_angle(angle) * 8.5 * scale
	canvas.draw_arc(handle, 3.6 * scale, 0.0, TAU, 12, RIM, 2.6 * scale, true)
	canvas.draw_arc(handle, 3.6 * scale, 0.0, TAU, 12, MUG_SHADE, 1.2 * scale, true)
	canvas.draw_circle(at, 7.6 * scale, RIM)
	canvas.draw_circle(at, 6.6 * scale, MUG)
	canvas.draw_circle(at, 5.0 * scale, COFFEE)
	canvas.draw_circle(at + Vector2(-1.6, -1.6) * scale, 1.4 * scale, COFFEE_SHINE)
