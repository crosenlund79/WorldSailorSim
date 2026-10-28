class_name RodHolder
extends Node2D
## The fishing rod in its holder on the stern rail (Iteration 13), drawn in
## the deck's coordinates (+x the bow, -y the port side). The rod leans aft
## and outboard over the water; with the line out a fine line trails astern,
## and a bite makes the rod tip nod. Presentation only: the station beside it
## opens the rod (FishingMenu).

const INK := Color("#1f2a2e")
const STEEL := Color("#9aa7ab")
const ROD := Color("#2c3b3f")
const CORK := Color("#A89068")
const REEL := Color("#5a6a6e")
const LINE := Color(0.95, 0.95, 0.9, 0.55)

## Where the rod tip sits, from the holder (aft and outboard).
const TIP := Vector2(-58.0, -34.0)

var _time := 0.0


func _ready() -> void:
	z_index = 2
	GameSession.fishing_changed.connect(queue_redraw)
	GameSession.fish_bite.connect(func(_bite: Dictionary) -> void: queue_redraw())


func _process(delta: float) -> void:
	_time += delta
	if GameSession.is_line_out():
		queue_redraw()


## The tip now: nodding while a fish is on.
func get_tip() -> Vector2:
	if GameSession.get_pending_bite().is_empty():
		return TIP
	return TIP + Vector2(6.0, 5.0) * (0.6 + 0.4 * sin(_time * 14.0))


## The holder and rod in this node's coordinates (for the highlight).
static func outline() -> PackedVector2Array:
	return PackedVector2Array([Vector2(12, 6), Vector2(8, 12), Vector2(TIP.x - 6, TIP.y + 4), Vector2(TIP.x - 8, TIP.y - 6),
		Vector2(-4, -12), Vector2(10, -8)])


func _draw() -> void:
	var tip := get_tip()
	if GameSession.is_line_out():
		# The line, sagging astern into the water.
		var end := tip + Vector2(-110.0, -26.0 + 4.0 * sin(_time * 1.3))
		var mid := (tip + end) / 2.0 + Vector2(0, 10)
		var points := PackedVector2Array()
		for k in 9:
			var t := k / 8.0
			points.append(tip.lerp(mid, t).lerp(mid.lerp(end, t), t))
		draw_polyline(points, LINE, 1.2, true)
		draw_circle(end, 3.0, Color(1, 1, 1, 0.25 + 0.15 * sin(_time * 2.0)))
	# The holder: a steel tube clamped to the rail.
	draw_circle(Vector2.ZERO, 7.0, INK)
	draw_circle(Vector2.ZERO, 5.0, STEEL)
	# The rod: a cork grip in the holder, the blank out to the tip.
	draw_line(Vector2(6, 4), Vector2.ZERO, INK, 6.0, true)
	draw_line(Vector2(5, 3.5), Vector2(-1, -0.5), CORK, 4.0, true)
	draw_line(Vector2.ZERO, tip, INK, 4.0, true)
	draw_line(Vector2.ZERO, tip, ROD, 2.2, true)
	draw_circle(tip, 1.8, Color("#c8553d"))
	# The reel, under the rod near the holder.
	var reel := Vector2(-9.0, -2.0)
	draw_circle(reel, 6.0, INK)
	draw_circle(reel, 4.4, REEL)
	draw_circle(reel, 1.6, STEEL)
