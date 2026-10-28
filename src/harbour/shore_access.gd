class_name ShoreAccess
extends Node2D
## Walking ashore (Iteration 12): a gangplank from the boat's rail down to the
## pontoon, and a small strip of pontoon to walk on, where the harbour's
## services stand (grocery store, boatyard, Go Ashore).
##
## Everything is derived from the boat's own layout, so every vessel works
## without per-boat numbers:
##   - the gangplank lands where the boat already puts a player arriving from
##     the boatyard (Layout/SpawnPoints/from_boatyard), straight down to the
##     pontoon (Surroundings/Mooring/Pontoon);
##   - the rail (Layout/Collision/Lifeline) is opened exactly where the plank
##     meets it: while ashore access is active the closed rail is replaced by
##     the same outline with a gap, the plank's two sides and the shore strip's
##     edges, so the boat, plank and pontoon form one walkable area with no
##     place to get stuck;
##   - underway, or when the boat is not in harbour, the original rail is
##     restored and the gangplank is gone.
## BoatArea owns it (decks with a mooring only) and places the shore
## stations in the slots it offers.

## Half the gangplank's walking width (the player's body radius is 20).
const PLANK_HALF := 34.0
## How far left and right of the middle the shore strip reaches.
const WALK_HALF := 520.0
## The back of the pontoon where the service signs stand (not walked on).
const SIGN_BAND := 38.0
## Distances of the service slots from the gangplank, in order of preference.
const SLOT_OFFSETS: Array[float] = [-215.0, 215.0, 430.0, -430.0]

# Real Horizon: an aluminium passerelle with non-slip treads and stainless
# hand rails.
const PLANK := Color("#A3AAAB")
const PLANK_DARK := Color("#6E7678")
const ROPE := Color("#C4CBCC")
const INK := Color("#2A3236")

var _area: BoatArea
var _active := false
var _pontoon := Rect2()
var _plank_x := 0.0
## Where the plank meets the rail (left and right edge) and the pontoon.
var _rail_left := Vector2.ZERO
var _rail_right := Vector2.ZERO
var _shore := Rect2()
var _original_rail: CollisionPolygon2D
var _body: StaticBody2D
var _base_bounds := Rect2()
var _ashore := false
var _valid := false


## Reads the deck's layout. Returns false (and stays inactive) when the deck
## lacks what it needs (no pontoon, rail or boarding point).
func setup(area: BoatArea) -> bool:
	_area = area
	_base_bounds = area.walkable_bounds
	var pontoon := area.get_node_or_null(^"Surroundings/Mooring/Pontoon") as Polygon2D
	_original_rail = area.get_node_or_null(^"Layout/Collision/Lifeline/CollisionPolygon2D") as CollisionPolygon2D
	var boarding := area.get_node_or_null(^"Layout/SpawnPoints/from_boatyard") as Node2D
	if pontoon == null or _original_rail == null or boarding == null:
		return false
	_pontoon = Rect2(area.to_local(pontoon.to_global(pontoon.polygon[0])), Vector2.ZERO)
	for p in pontoon.polygon:
		_pontoon = _pontoon.expand(area.to_local(pontoon.to_global(p)))
	_plank_x = boarding.position.x
	var rail := _rail_points()
	var left := _crossing(rail, _plank_x - PLANK_HALF)
	var right := _crossing(rail, _plank_x + PLANK_HALF)
	if left.is_empty() or right.is_empty():
		return false
	_rail_left = left.point
	_rail_right = right.point
	var x0 := maxf(_pontoon.position.x + 10.0, -WALK_HALF)
	var x1 := minf(_pontoon.end.x - 10.0, WALK_HALF)
	_shore = Rect2(x0, _pontoon.position.y + 2.0, x1 - x0, _pontoon.size.y - 2.0 - SIGN_BAND)
	_build_body(rail, left, right)
	_valid = true
	return true


func is_valid() -> bool:
	return _valid


## Shore access on (in harbour) or off (underway): swaps the rail, shows the
## gangplank and widens the area a restored position may lie in.
func set_active(active: bool) -> void:
	if not _valid:
		return
	_active = active
	visible = active
	_original_rail.set_deferred(&"disabled", active)
	for child in _body.get_children():
		(child as CollisionShape2D).set_deferred(&"disabled", not active)
	_area.walkable_bounds = _base_bounds.merge(_shore.grow(4.0)) if active else _base_bounds
	queue_redraw()


## The boat's own walkable area (without the shore).
func get_boat_bounds() -> Rect2:
	return _base_bounds


func is_active() -> bool:
	return _active


func get_plank_x() -> float:
	return _plank_x


## The walkable shore strip (BoatArea coordinates).
func get_shore_rect() -> Rect2:
	return _shore


func get_pontoon_rect() -> Rect2:
	return _pontoon


## y of the rail where the plank starts (the boat's side of the gangplank).
func get_rail_y() -> float:
	return maxf(_rail_left.y, _rail_right.y)


## A point in the middle of the shore strip below the gangplank.
func get_landing_point() -> Vector2:
	return Vector2(_plank_x, _shore.position.y + 24.0)


## True when `p` (BoatArea coordinates) is on the gangplank or ashore.
func is_off_the_boat(p: Vector2) -> bool:
	return _active and p.y > get_rail_y() + 4.0


## Slots for `count` services along the shore, never on the gangplank's path:
## the sign's centre (on the back of the pontoon) and the station's centre
## in front of it.
func get_service_slots(count: int) -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	for offset in SLOT_OFFSETS:
		if slots.size() >= count:
			break
		var x := _plank_x + offset
		if x < _shore.position.x + 80.0 or x > _shore.end.x - 80.0:
			continue
		slots.append({"sign": Vector2(x, _pontoon.end.y - SIGN_BAND / 2.0), "station": Vector2(x, _shore.end.y - 18.0)})
	return slots


## Tracks the player crossing the gangplank (for the diagnostic log).
func update_player(p: Vector2) -> void:
	var ashore := is_off_the_boat(p) and p.y > _pontoon.position.y
	if ashore == _ashore:
		return
	_ashore = ashore
	SessionLog.write("gangplank", {"to": "shore" if ashore else "boat", "vessel": String(GameSession.get_vessel_id()),
		"port": String(GameSession.get_location_id())})


func is_player_ashore() -> bool:
	return _ashore


# --- Geometry --------------------------------------------------------------------

func _rail_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	for p in _original_rail.polygon:
		points.append(_area.to_local(_original_rail.to_global(p)))
	return points


## Where the vertical line at `x` crosses the rail on its pontoon side (the
## crossing with the largest y): {"point", "edge", "t"}, or {} if none.
static func _crossing(points: PackedVector2Array, x: float) -> Dictionary:
	var best := {}
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		if is_equal_approx(a.x, b.x) or (a.x - x) * (b.x - x) > 0.0:
			continue
		var t := (x - a.x) / (b.x - a.x)
		var p := a.lerp(b, t)
		if best.is_empty() or p.y > best.point.y:
			best = {"point": p, "edge": i, "t": t}
	return best


## The rail as an open path that leaves out the stretch between the two
## crossings, plus the gangplank's sides and the shore strip with its gap.
func _build_body(rail: PackedVector2Array, left: Dictionary, right: Dictionary) -> void:
	var n := rail.size()
	var path := PackedVector2Array()
	var i0: int = left.edge
	var i1: int = right.edge
	# The gap is the short stretch of rail between the crossings: the vertices
	# met going forward from the left crossing, if they all lie within the
	# plank's width; otherwise it runs the other way round.
	var forward := PackedVector2Array()
	var k := (i0 + 1) % n
	var steps := 0
	while k != (i1 + 1) % n and steps < n:
		forward.append(rail[k])
		k = (k + 1) % n
		steps += 1
	var gap_forward := true
	if i0 == i1:
		gap_forward = float(left.t) <= float(right.t)
	else:
		for p in forward:
			if p.x < _plank_x - PLANK_HALF - 1.0 or p.x > _plank_x + PLANK_HALF + 1.0:
				gap_forward = false
				break
	if gap_forward:
		# p_right, vertices after the right crossing's edge ... up to the left one, p_left.
		path.append(right.point)
		k = (i1 + 1) % n
		for s in n:
			path.append(rail[k])
			if k == i0:
				break
			k = (k + 1) % n
		path.append(left.point)
	else:
		path.append(left.point)
		k = (i0 + 1) % n
		for s in n:
			path.append(rail[k])
			if k == i1:
				break
			k = (k + 1) % n
		path.append(right.point)
	_body = StaticBody2D.new()
	_body.name = "ShoreCollision"
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	for s in path.size() - 1:
		_segment(path[s], path[s + 1])
	var top := _shore.position.y
	var x_left := _plank_x - PLANK_HALF
	var x_right := _plank_x + PLANK_HALF
	# The plank's sides, down to the pontoon.
	_segment(_rail_left, Vector2(x_left, top))
	_segment(_rail_right, Vector2(x_right, top))
	# The shore strip, open where the plank arrives.
	_segment(Vector2(_shore.position.x, top), Vector2(x_left, top))
	_segment(Vector2(x_right, top), Vector2(_shore.end.x, top))
	_segment(Vector2(_shore.position.x, top), Vector2(_shore.position.x, _shore.end.y))
	_segment(Vector2(_shore.end.x, top), _shore.end)
	_segment(Vector2(_shore.position.x, _shore.end.y), _shore.end)


func _segment(a: Vector2, b: Vector2) -> void:
	if a.distance_to(b) < 0.5:
		return
	var shape := SegmentShape2D.new()
	shape.a = a
	shape.b = b
	var owner_shape := CollisionShape2D.new()
	owner_shape.shape = shape
	owner_shape.disabled = true
	_body.add_child(owner_shape)


# --- Drawing ---------------------------------------------------------------------

func _draw() -> void:
	if not _active:
		return
	var top := get_rail_y() - 14.0
	var bottom := _pontoon.position.y + 16.0
	var x0 := _plank_x - PLANK_HALF + 2.0
	var x1 := _plank_x + PLANK_HALF - 2.0
	# Shadow on the water, the boards, the cleats across them, the hand ropes.
	draw_rect(Rect2(x0 + 6, top + 9, x1 - x0, bottom - top), Color(0.04, 0.07, 0.09, 0.3))
	draw_rect(Rect2(x0, top, x1 - x0, bottom - top), PLANK)
	# Side beams and the non-slip treads between them.
	draw_rect(Rect2(x0, top, 4, bottom - top), PLANK_DARK)
	draw_rect(Rect2(x1 - 4, top, 4, bottom - top), PLANK_DARK)
	var y := top + 7.0
	while y < bottom - 4.0:
		draw_rect(Rect2(x0 + 6, y, x1 - x0 - 12, 3.0), Color("#3A4144"))
		y += 11.0
	draw_rect(Rect2(x0, top, x1 - x0, bottom - top), Color(INK, 0.7), false, 1.2)
	for x in [x0 - 4.0, x1 + 4.0]:
		draw_line(Vector2(x, top - 4), Vector2(x, bottom + 2), Color(INK, 0.6), 3.0, true)
		draw_line(Vector2(x, top - 4), Vector2(x, bottom + 2), ROPE, 1.6, true)
		for post_y in [top - 4.0, bottom + 2.0]:
			draw_circle(Vector2(x, post_y), 3.2, Color(INK, 0.7))
			draw_circle(Vector2(x, post_y), 2.2, ROPE)
