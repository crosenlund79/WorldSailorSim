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
	# I027 playtest: redrawn in the illustrated style of the deck - a tapered
	# blank with a soft highlight and guides, a cork grip, a spinning reel seen
	# from above and a stainless holder, outlined lightly (as the people are)
	# rather than in heavy ink. The tip and its nod are unchanged.
	var ink := Color(INK, 0.55)
	var along := tip.normalized()
	var side := Vector2(-along.y, along.x)
	# A soft shadow of the rod on the water and the deck below it.
	draw_line(Vector2(3, 5), tip + Vector2(5, 8), Color(0, 0, 0, 0.16), 3.0, true)
	# The holder: a short stainless tube clamped to the rail.
	draw_circle(Vector2.ZERO, 5.6, ink)
	draw_circle(Vector2.ZERO, 4.6, STEEL)
	draw_circle(Vector2(-1.0, -1.2), 2.0, Color(1, 1, 1, 0.45))
	# The blank: tapering from the butt to the tip, in segments.
	var length := tip.length()
	var segments := 8
	for k in segments:
		var a := along * length * (float(k) / segments)
		var b := along * length * (float(k + 1) / segments)
		var width := lerpf(3.0, 1.0, float(k) / segments)
		draw_line(a, b, ink, width + 1.2, true)
		draw_line(a, b, ROD, width, true)
	draw_line(along * 4.0 + side * 0.6, tip * 0.8 + side * 0.4, Color(1, 1, 1, 0.22), 0.8, true)  # the varnish's highlight
	# The guides: small rings along the blank, closer towards the tip.
	for t: float in [0.32, 0.55, 0.73, 0.88]:
		draw_arc(along * length * t, lerpf(2.2, 1.2, t), 0.0, TAU, 10, Color(STEEL, 0.9), 0.7, true)
	draw_circle(tip, 1.5, Color("#c8553d"))  # the painted tip
	# The grip: cork with its rings, below the holder's clamp.
	var butt := -along * 9.0
	draw_line(butt, Vector2.ZERO, ink, 5.0, true)
	draw_line(butt, Vector2.ZERO, CORK, 3.8, true)
	for t: float in [0.3, 0.65]:
		var at := butt.lerp(Vector2.ZERO, t)
		draw_line(at - side * 1.8, at + side * 1.8, Color(CORK.darkened(0.25), 0.8), 0.6, true)
	draw_circle(butt, 2.0, Color(REEL, 0.95))  # the butt cap
	# The reel: a spinning reel under the rod, its spool and bail seen from above.
	var reel := along * 9.0 - side * 4.5
	draw_line(along * 9.0, reel, Color(REEL, 0.9), 1.4, true)  # its foot
	var body := PackedVector2Array([reel + along * 4.5 + side * 2.6, reel + along * 4.5 - side * 2.6,
		reel - along * 3.5 - side * 3.0, reel - along * 3.5 + side * 3.0])
	draw_colored_polygon(body, REEL)
	draw_polyline(body + PackedVector2Array([body[0]]), ink, 0.7, true)
	draw_circle(reel + along * 3.2, 2.4, STEEL)  # the spool
	draw_arc(reel + along * 3.2, 3.6, along.angle() - 1.4, along.angle() + 1.4, 8, Color(STEEL, 0.9), 0.6, true)  # the bail
	draw_line(reel - side * 3.0, reel - side * 6.0 - along * 1.5, Color(REEL, 0.9), 0.9, true)  # the handle
	draw_circle(reel - side * 6.0 - along * 1.5, 1.1, CORK)
