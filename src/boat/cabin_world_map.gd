class_name CabinWorldMap
extends Node2D
## The framed world map on the cabin wall (Iteration 17): an illustrated
## chart of the whole world in a wooden frame, drawn from the game's one
## world land data (the chart's overview layer, scaled down), with small pins
## for the harbours visited and the boat's position. Interacting with it
## (its Interactable child, "world_map") opens the Dreamer's Map.
##
## Drawing cost: the land is triangulated once per game run (static cache,
## shared by all four boats), then drawn as one triangle batch; the pins are
## redrawn only when the cabin is entered. Nothing here samples the weather.

## Outer size of the frame, in cabin units (picture plus frame).
@export var size := Vector2(150, 84):
	set(value):
		size = value
		queue_redraw()
## Latitudes shown (the map is cropped like a wall chart: no polar caps).
const NORTH := 78.0
const SOUTH := -58.0
# Real Horizon: a chart print of the world in a slim anodised frame, in the
# paper chart's own colours (pale sea, buff land).
const FRAME := Color("#5E676B")
const FRAME_LIGHT := Color("#9AA3A6")
const PAPER := Color("#DCDBD2")
const SEA := Color("#BCCDD2")
const LAND := Color("#D2C9A8")
const LAND_EDGE := Color("#8C8670")
const PIN := Color("#B5523F")
const BOAT := Color("#1F2D38")
const FRAME_WIDTH := 7.0

static var _triangles := PackedVector2Array()
static var _built := false


func _ready() -> void:
	add_to_group(HighlightResolver.GROUP)
	set_meta(HighlightResolver.META_FOR, &"world_map")


## The picture's area inside the frame (local coordinates, centred).
func get_picture_rect() -> Rect2:
	var inner := size - Vector2.ONE * FRAME_WIDTH * 2.0
	return Rect2(-inner / 2.0, inner)


## Outline for the interaction highlight (global points).
func get_highlight_outline() -> PackedVector2Array:
	var r := Rect2(-size / 2.0, size).grow(3.0)
	return PackedVector2Array([to_global(r.position), to_global(Vector2(r.end.x, r.position.y)), to_global(r.end),
		to_global(Vector2(r.position.x, r.end.y))])


## Unit-square position (0..1) of a longitude/latitude on the wall chart
## (Mercator, like the game's charts, cropped to NORTH..SOUTH).
static func to_unit(geo: Vector2) -> Vector2:
	var top := _mercator_y(NORTH)
	var bottom := _mercator_y(SOUTH)
	return Vector2((geo.x + 180.0) / 360.0, (top - _mercator_y(clampf(geo.y, SOUTH, NORTH))) / (top - bottom))


static func _mercator_y(lat: float) -> float:
	return log(tan(PI / 4.0 + deg_to_rad(lat) / 2.0))


## Paper width over paper height of the unit square (keeps shapes true).
static func aspect() -> float:
	return TAU / (_mercator_y(NORTH) - _mercator_y(SOUTH))


## The land triangles (unit square), their indices and a white colour per
## point, built once and shared (the voyage map draws them scaled and tinted).
static func land_triangles() -> PackedVector2Array:
	return _land_triangles()


static var _indices := PackedInt32Array()
static var _white := PackedColorArray()


static func land_indices() -> PackedInt32Array:
	var count := _land_triangles().size()
	if _indices.size() != count:
		_indices.resize(count)
		for i in count:
			_indices[i] = i
		_white.resize(count)
		_white.fill(Color.WHITE)
	return _indices


static func land_colours() -> PackedColorArray:
	land_indices()
	return _white


## The world's land as triangles in unit-square coordinates (built once).
static func _land_triangles() -> PackedVector2Array:
	if _built:
		return _triangles
	_built = true
	var land := load(MapView.WORLD_LAND_RES) as WorldLand if ResourceLoader.exists(MapView.WORLD_LAND_RES) else null
	if land == null:
		return _triangles
	var projection := MapProjection.new(land.scale)
	for ring in land.overview_fill:
		if ring.size() < 3:
			continue
		var indices := Geometry2D.triangulate_polygon(ring)
		if indices.is_empty():
			continue
		for index in indices:
			_triangles.append(to_unit(projection.map_to_geo(ring[index])))
	return _triangles


func _draw() -> void:
	var outer := Rect2(-size / 2.0, size)
	# A soft shadow on the bulkhead, then the frame and the paper.
	draw_rect(outer.grow(2.0).grow_individual(0, 0, 2, 3), Color(0, 0, 0, 0.25))
	draw_rect(outer, FRAME)
	draw_rect(outer.grow(-2.0), FRAME_LIGHT, false, 1.5)
	var picture := get_picture_rect()
	draw_rect(picture.grow(1.0), PAPER)
	draw_rect(picture, SEA)
	var triangles := _land_triangles()
	if not triangles.is_empty():
		var points := PackedVector2Array()
		points.resize(triangles.size())
		for i in triangles.size():
			points[i] = picture.position + triangles[i] * picture.size
		var colors := PackedColorArray()
		colors.resize(points.size())
		colors.fill(LAND)
		var indices := PackedInt32Array()
		indices.resize(points.size())
		for i in points.size():
			indices[i] = i
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, points, colors)
	draw_rect(picture, LAND_EDGE, false, 1.0)
	# A tiny compass rose in the southern ocean corner.
	var rose := picture.position + Vector2(picture.size.x * 0.08, picture.size.y * 0.86)
	draw_line(rose + Vector2(0, -5), rose + Vector2(0, 5), BOAT, 1.0)
	draw_line(rose + Vector2(-5, 0), rose + Vector2(5, 0), BOAT, 1.0)
	draw_circle(rose + Vector2(0, -6), 1.2, PIN)
	if not GameSession.is_active():
		return
	# Pins: the harbours visited, and the boat.
	var catalog := PortCatalog.get_default()
	for id in GameSession.get_captains_log().get_visited_ids():
		var port := catalog.get_port(id)
		if port:
			draw_circle(picture.position + to_unit(port.get_geo_position()) * picture.size, 1.4, PIN)
	var boat := picture.position + to_unit(GameSession.get_vessel_position()) * picture.size
	draw_circle(boat, 2.4, PAPER)
	draw_circle(boat, 1.6, BOAT)
