class_name WinchProp
extends Node2D
## The genoa sheet winch on the cockpit coaming (I026, A World You Can
## Touch): where a sailor trims. E on it opens the same sail trim as T and
## the action wheel (SailTrimPanel; under way only - App says why not
## otherwise). Placed by BoatArea at the forward end of the starboard cockpit
## bench (the Clam 40: beside the wheel), drawn at true scale (a self-tailing
## winch about 20 cm across) with a winch handle in its pocket. No
## collision: never in the Captain's or a companion's way.

const RADIUS := 9.0
const DRUM := Color("#B7BEC2")
const DRUM_DARK := Color("#80898E")
const TOP := Color("#2E3438")
const HANDLE := Color("#3C4348")

var interactable: Interactable


## Puts the winch on `area`'s deck (decks with a cockpit bench or a wheel).
static func place(area: Node2D) -> WinchProp:
	var collision := area.get_node_or_null(^"Layout/Collision")
	if collision == null:
		return null
	var at := Vector2.INF
	var bench := collision.get_node_or_null(^"BenchStarboard") as BoatFixture
	if bench:
		var points := bench.transform * bench.get_points()
		var fwd := -INF
		var out := 0.0
		for p in points:
			fwd = maxf(fwd, p.x)
			out = p.y if absf(p.y) > absf(out) else out
		at = Vector2(fwd - 10.0, out - signf(out) * 6.0)
	else:
		var wheel := collision.get_node_or_null(^"Wheel") as Node2D
		if wheel:
			at = wheel.position + Vector2(26.0, -signf(wheel.position.y) * 30.0 if not is_zero_approx(wheel.position.y) else 30.0)
	if at == Vector2.INF:
		return null
	var winch := WinchProp.new()
	winch.name = "Winch"
	winch.position = at
	winch.z_index = 2
	area.add_child(winch)
	return winch


func _ready() -> void:
	interactable = Interactable.new()
	interactable.name = "Trim"
	interactable.interaction_id = &"trim"
	interactable.prompt = Loc.t("Trim the sails")
	interactable.focus_priority = -1  # the helm and the plotter keep precedence nearby
	interactable.highlight_target = ^""
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 30.0
	shape.shape = circle
	interactable.add_child(shape)
	add_child(interactable)
	interactable.set_highlight_outline_global(_outline())


func _outline() -> PackedVector2Array:
	var points := PackedVector2Array()
	for p in HighlightResolver.circle(Vector2.ZERO, RADIUS + 3.0, 20):
		points.append(to_global(p))
	return points


func _draw() -> void:
	draw_circle(Vector2(1.5, 2.0), RADIUS + 1.0, Color(0.03, 0.05, 0.06, 0.3))
	draw_circle(Vector2.ZERO, RADIUS, DRUM_DARK)
	draw_circle(Vector2(-0.8, -0.8), RADIUS - 1.6, DRUM)
	# The self-tailing jaws and the top, the handle socket in the middle.
	draw_arc(Vector2.ZERO, RADIUS - 2.2, 0.0, TAU, 20, DRUM_DARK, 1.0, true)
	draw_circle(Vector2.ZERO, RADIUS * 0.45, TOP)
	draw_circle(Vector2.ZERO, 1.6, DRUM)
	# The winch handle, stowed in its pocket beside it.
	draw_line(Vector2(RADIUS + 3.0, -2.0), Vector2(RADIUS + 13.0, -2.0), HANDLE, 2.2, true)
	draw_circle(Vector2(RADIUS + 13.0, -2.0), 1.8, HANDLE)
