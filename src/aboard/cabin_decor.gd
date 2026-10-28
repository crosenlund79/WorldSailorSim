class_name CabinDecor
extends Node2D
## One of the Captain's cabin things (I020, A Boat of Your Own): a braided
## rug, a pot of herbs, a framed old chart, a brass oil lamp, a shelf of sea
## stories, signal-flag bunting. Drawn in the cabin's own hand-drawn manner
## (a few shapes and an outline, no sprites), purely a look: no collision, no
## station, nothing to walk around.
##
## Where each goes is found from the cabin itself (place_all): things for the
## walls on the hull side, the rug on open floor, all clear of every station
## and the companion's resting spots, so nothing ever covers the galley, the
## chart table, a berth or the coffee spots. The same cabin always gives the
## same places.

const INK := Color("#2A3236")
const RUG_A := Color("#6F5C4E")
const RUG_B := Color("#A9A293")
const RUG_C := Color("#58676B")
const WOOD := Color("#5E4C3C")
const BRASS := Color("#A88F5A")
const GLASS := Color(1.0, 0.93, 0.78, 0.8)
const PAPER := Color("#DCDBD2")
const SEA := Color("#A9BCC2")
const LEAF := Color("#56664A")
const POT := Color("#8A5A44")
const FLAGS: Array[Color] = [Color("#B23A32"), Color("#D8B24A"), Color("#2A4F7A"), Color("#E8E8E2"), Color("#1E2328")]
const BOOKS: Array[Color] = [Color("#6C4A40"), Color("#3E556A"), Color("#4F5E4A"), Color("#8E8064"), Color("#585560")]

## Keep this far from stations and companion spots (px), and this far apart.
const CLEARANCE := 46.0
const SPACING := 70.0
const RUG_RADIUS := 36.0
## Drawn a little larger than the sizes below (they read at cabin zoom).
const DRAW_SCALE := 1.4

var item_id := ""
## +1: on the starboard wall (facing up, into the cabin), -1: port; 0: floor.
var side := 1.0


func _ready() -> void:
	scale = Vector2.ONE * DRAW_SCALE if item_id != "rug" else Vector2.ONE


func _draw() -> void:
	match item_id:
		"rug":
			_draw_rug()
		"herbs":
			_draw_herbs()
		"chart_print":
			_draw_chart()
		"oil_lamp":
			_draw_lamp()
		"books":
			_draw_books()
		"bunting":
			_draw_bunting()


## Local "inward" direction (from the wall into the cabin).
func _in() -> Vector2:
	return Vector2(0.0, -side)


func _draw_rug() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.72))
	for ring in [[RUG_RADIUS, RUG_A], [RUG_RADIUS - 7.0, RUG_B], [RUG_RADIUS - 13.0, RUG_C], [RUG_RADIUS - 19.0, RUG_A],
			[RUG_RADIUS - 25.0, RUG_B]]:
		draw_circle(Vector2.ZERO, ring[0], ring[1])
	draw_arc(Vector2.ZERO, RUG_RADIUS, 0.0, TAU, 40, INK * Color(1, 1, 1, 0.5), 1.5, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_herbs() -> void:
	var into := _in()
	var base := into * 4.0
	draw_rect(Rect2(base + Vector2(-9, -7), Vector2(18, 14)), POT)
	draw_rect(Rect2(base + Vector2(-9, -7), Vector2(18, 14)), INK, false, 1.5)
	for k in 5:
		var at := base + into * 9.0 + Vector2((k - 2) * 5.0, sin(k * 1.7) * 3.0)
		draw_circle(at, 5.0, LEAF.lightened(0.08 * (k % 2)))
	draw_circle(base + into * 9.0, 2.0, LEAF.darkened(0.3))


func _draw_chart() -> void:
	var frame := Rect2(Vector2(-22, -5) + _in() * 6.0 - Vector2(0, 0), Vector2(44, 10))
	draw_rect(frame.grow(3.0), WOOD)
	draw_rect(frame, PAPER)
	draw_line(frame.position + Vector2(4, frame.size.y * 0.6), frame.end - Vector2(12, frame.size.y * 0.3), SEA, 2.0)
	draw_circle(frame.position + Vector2(30, 5), 2.0, SEA)
	draw_rect(frame.grow(3.0), INK, false, 1.5)


func _draw_lamp() -> void:
	var into := _in()
	draw_line(Vector2.ZERO, into * 6.0, BRASS.darkened(0.3), 2.0)
	draw_circle(into * 12.0, 9.0, Color(GLASS, 0.25))
	draw_circle(into * 12.0, 6.0, GLASS)
	draw_arc(into * 12.0, 6.0, 0.0, TAU, 20, BRASS, 2.5, true)
	draw_circle(into * 12.0, 2.0, Color("#F2DEB0"))


func _draw_books() -> void:
	var into := _in()
	var shelf := Rect2(Vector2(-24, 0) + (into * 2.0 if side > 0 else Vector2.ZERO), Vector2(48, 4))
	draw_rect(shelf, WOOD)
	for k in 7:
		var width := 4.0 + float(k % 3)
		var x := -22.0 + k * 6.6
		var spine := Rect2(Vector2(x, 0.0) + into * 4.0 + (Vector2(0, -8) if side > 0 else Vector2.ZERO), Vector2(width, 8.0))
		draw_rect(spine, BOOKS[k % BOOKS.size()])
	draw_rect(shelf, INK, false, 1.0)


func _draw_bunting() -> void:
	var into := _in()
	var span := 70.0
	var points := PackedVector2Array()
	for k in 9:
		var t := k / 8.0
		points.append(Vector2(-span / 2.0 + span * t, 0.0) + into * (2.0 + 6.0 * sin(PI * t)))
	draw_polyline(points, INK, 1.2, true)
	for k in 8:
		var a: Vector2 = points[k]
		var b: Vector2 = points[k + 1]
		draw_colored_polygon(PackedVector2Array([a, b, (a + b) / 2.0 + into * 8.0]), FLAGS[k % FLAGS.size()])


# --- Where things go ----------------------------------------------------------------------

## The places for `items` (decor ids, in catalogue order) in a cabin:
## {id: [position, side]}. `hull`: the cabin's walkable outline; `fixtures`:
## furniture outlines (global polygons); `avoid`: stations, companion spots
## and fitted gear. Things for the walls go on the hull side, alternating
## starboard and port, spread along the boat; the rug on open floor nearest
## the cabin's middle. A thing with no clear place is not shown.
static func place_all(items: Array[String], hull: PackedVector2Array, fixtures: Array[PackedVector2Array],
		avoid: Array[Vector2]) -> Dictionary:
	var placed := {}
	if hull.size() < 3:
		return placed
	var bounds := Rect2(hull[0], Vector2.ZERO)
	for p in hull:
		bounds = bounds.expand(p)
	var taken: Array[Vector2] = []
	var wall_index := 0
	for id in items:
		var where := HarbourTrades.get_decor_item(id).get("place", "wall") as String
		if where == "floor":
			var rug := _floor_spot(hull, bounds, fixtures, avoid)
			if rug != Vector2.INF:
				placed[id] = [rug, 0.0]
			continue
		var spot := _wall_spot(hull, bounds, avoid, taken, 1.0 if wall_index % 2 == 0 else -1.0)
		if spot.is_empty():
			spot = _wall_spot(hull, bounds, avoid, taken, -1.0 if wall_index % 2 == 0 else 1.0)
		if not spot.is_empty():
			placed[id] = spot
			taken.append(spot[0])
		wall_index += 1
	return placed


static func _wall_spot(hull: PackedVector2Array, bounds: Rect2, avoid: Array[Vector2], taken: Array[Vector2], side: float) -> Array:
	# Candidates from the middle of the cabin outwards, so the things gather
	# where the Captain lives (the saloon) before the ends.
	var middle := bounds.get_center().x
	var span := bounds.size.x * 0.42
	for k in 41:
		var x := middle + (k + 1) / 2 * 20.0 * (1.0 if k % 2 == 0 else -1.0)
		if absf(x - middle) > span:
			continue
		var edge := _wall_y(hull, x, side)
		if is_nan(edge):
			continue
		var at := Vector2(x, edge - side * 6.0)
		if _clear(at, avoid, CLEARANCE) and _clear(at, taken, SPACING):
			return [at, side]
	return []


## The hull's wall at `x` on `side` (+1 starboard, larger y), or NAN.
static func _wall_y(hull: PackedVector2Array, x: float, side: float) -> float:
	var y := 0.0
	if not Geometry2D.is_point_in_polygon(Vector2(x, 0.0), hull):
		return NAN
	while absf(y) < 600.0 and Geometry2D.is_point_in_polygon(Vector2(x, y + side * 2.0), hull):
		y += side * 2.0
	return y


static func _floor_spot(hull: PackedVector2Array, bounds: Rect2, fixtures: Array[PackedVector2Array], avoid: Array[Vector2]) -> Vector2:
	var best := Vector2.INF
	var middle := bounds.get_center()
	for gx in range(int(bounds.position.x), int(bounds.end.x), 10):
		for gy in range(int(bounds.position.y), int(bounds.end.y), 10):
			var at := Vector2(gx, gy)
			if at.distance_to(middle) >= best.distance_to(middle) and best != Vector2.INF:
				continue
			# Clear of the stations and of the companion's spots (its bed).
			if not _rug_fits(at, hull, fixtures) or not _clear(at, avoid, RUG_RADIUS + 24.0):
				continue
			best = at
	return best


## The rug (an ellipse) lies on open floor: inside the cabin and clear of
## every piece of furniture.
static func _rug_fits(at: Vector2, hull: PackedVector2Array, fixtures: Array[PackedVector2Array]) -> bool:
	for k in 12:
		var angle := TAU * k / 12.0
		var p := at + Vector2(cos(angle) * RUG_RADIUS, sin(angle) * RUG_RADIUS * 0.72)
		if not Geometry2D.is_point_in_polygon(p, hull):
			return false
		for shape in fixtures:
			if Geometry2D.is_point_in_polygon(p, shape):
				return false
	for shape in fixtures:
		if Geometry2D.is_point_in_polygon(at, shape):
			return false
	return true


static func _clear(at: Vector2, points: Array[Vector2], distance: float) -> bool:
	for p in points:
		if p.distance_to(at) < distance:
			return false
	return true
