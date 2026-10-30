class_name MapView
extends Node2D
## Draws the navigation chart and turns mouse/keyboard input into chart events.
##
## Geography comes from `land_data` (longitude/latitude polygons), ports from
## the port catalog and weather from the weather catalog; MapProjection turns
## coordinates into map units and the Camera2D maps those to the screen.
## Nothing here stores screen or map-space positions in game data. MapView
## only displays courses and reports clicks/drags; WorldMap decides what they mean.
##
## Performance: land is pre-split into tiles (cheap triangulation), coastlines
## are drawn once as hairlines that never need redrawing, and only the light
## overlay (routes, markers, labels) is redrawn when the view changes.

signal port_clicked(port_id: StringName)
## A click on the chart that hit nothing in particular.
signal map_clicked(geo: Vector2)
## Pressed on the editable course, leg `leg_index`, at `geo`.
signal route_pressed(leg_index: int, geo: Vector2)
signal waypoint_pressed(index: int)
signal waypoint_dragged(index: int, geo: Vector2)
signal waypoint_released(index: int, geo: Vector2)
signal waypoint_remove_requested(index: int)
## Cursor position in geographic coordinates, or null when not over the map.
signal cursor_moved(geo: Variant)
## A Detailed Cruising Region's chart mark or a named anchorage was clicked,
## or the mark / anchorage under the cursor changed (Regions and Harbours 2026).
signal cruising_region_clicked(id: StringName)
signal anchorage_clicked(id: StringName)
signal cruising_hover_changed()

@export var land_data: JSON
@export var units_per_degree := 160.0
@export var min_zoom := 0.02
@export var max_zoom := 10.0
@export var keyboard_pan_speed := 900.0
## Screen pixels on the right covered by UI (the chart's side panel). The view
## is centred and fitted within the remaining area.
@export var occluded_right_px := 0.0

# Real Horizon: a modern chartplotter's dusk palette - deep slate water,
# muted khaki land with a pale coastline for clear separation, white
# soundings-free labels, magenta for the route (the chart convention) and
# instrument cyan for waypoints and proposals.
const WATER := Color("#1B3340")
const WATER_EDGE := Color("#12232C")
const LAND := Color("#8E8B74")
const COAST := Color("#D6D2BC")
const GRID := Color(0.353, 0.659, 0.722, 0.14)
const GRID_TEXT := Color(0.62, 0.74, 0.77, 0.7)
const PORT_FILL := Color("#EEF2F1")
const PORT_RIM := Color("#0E1A21")
const BRASS := Color("#D46CA4")
const SEAFOAM := Color("#5AA8B8")
const HOVER := Color("#7FC3D0")
const INVALID := Color("#E0A657")
const LABEL_COUNTRY := Color(0.17, 0.18, 0.15, 0.72)
const LABEL_SEA := Color(0.62, 0.76, 0.79, 0.55)
## How often (game seconds) the weather overlay follows the moving events.
const WEATHER_REFRESH_SECONDS := 300.0

const LABEL_FONT: Font = preload("res://assets/fonts/Barlow-SemiBold.ttf")
const PICK_RADIUS_PX := 18.0
const WAYPOINT_PICK_PX := 14.0
const ROUTE_PICK_PX := 8.0
const ZOOM_STEP := 1.25
const CLICK_SLOP_PX := 6.0
## Coastline drawing is split into runs of at most this many points, grouped
## into square tiles of this many map units, so off-screen tiles are culled.
const COAST_RUN_POINTS := 128
const COAST_TILE_UNITS := 400.0
## Harbour markers by zoom: screen pixels per degree of longitude from which
## harbours of importance 1, 2 and 3 get a marker (PortData.importance).
const PORT_MARKER_PX_PER_DEGREE: Array[float] = [0.0, 0.0, 45.0, 110.0]
## Harbour label font size (screen pixels) and the gap kept between labels.
const PORT_LABEL_PX := 21.0
const PORT_LABEL_GAP_PX := 4.0
## The world chart (Iteration 16): below this zoom (screen pixels per degree)
## the whole world is drawn coarsely; from it on, Europe's own chart and the
## world's regional land outside Europe.
const EUROPE_DETAIL_PX := 9.0
## Europe's own country and sea names appear from this zoom (px per degree):
## below it they would crowd the harbours of a small-scale chart.
const EUROPE_LABEL_PX := 16.0
const WORLD_META := "res://data/navigation/world/world.json"
const WORLD_LAND := "res://data/navigation/world/land.json"
## The same land, projected and binary (tools/navigation/world_land_to_res.gd).
const WORLD_LAND_RES := "res://data/navigation/world/land.res"
## At world zoom, harbour markers closer than this (screen pixels) to a more
## important one are left out, so a click always hits the intended harbour.
const DECLUTTER_PX := 16.0
## Detailed Cruising Regions (Regions and Harbours 2026): each region's quiet
## mark (a small symbol, its name and a dashed accent along its waters) shows
## on the zoomed-out chart and fades out by CRUISING_MARK_MAX_PX, where the
## region's own harbours take over. Named anchorages get a small anchor from
## ANCHORAGE_MARKER_PX (the zoom of the smallest harbours) and a name where
## there is room from ANCHORAGE_LABEL_PX.
const CRUISING_MARK_MAX_PX := 60.0
const CRUISING_ACCENT := Color("#C9B27E")
const ANCHORAGE_MARKER_PX := 110.0
const ANCHORAGE_LABEL_PX := 200.0
const CRUISING_PICK_PX := 14.0
## The regions' names join their symbols from this zoom (the whole-world view
## keeps to the symbols, clear of the harbour names).
const CRUISING_NAME_MIN_PX := 8.0
const ISLET_COLOUR := Color("#7F7C66")

## ROUTE: pressed on a course line; it becomes a new waypoint only when dragged
## (Cozy Polish: a plain click on the line no longer drops a waypoint).
enum Press { NONE, PENDING, PAN, WAYPOINT, REMOVE, ROUTE }

var projection: MapProjection
var catalog: PortCatalog

## Display state, set by WorldMap through set_display().
var boat_port_id: StringName
var selected_port_id: StringName
var destination_port_id: StringName
var vessel_geo := Vector2.INF
## Active voyage course: travelled part and part still ahead.
var travelled_path := PackedVector2Array()
var active_path := PackedVector2Array()
## The course being planned or edited: [{"path": PackedVector2Array, "ok": bool}].
var draft_legs: Array[Dictionary] = []
## True while the draft differs from the committed course (drawn differently).
var draft_is_proposal := false
var waypoints: Array[Vector2] = []
## Which waypoints are anchorages (Iteration 18): drawn with an anchor.
var anchorages: Array[bool] = []
## Which of them need the Magic Anchor (0.105b): drawn in amber.
var anchorage_magic: Array[bool] = []
const MAGIC_AMBER := Color("#D9A85A")
var invalid_waypoints := PackedInt32Array()
var selected_waypoint := -1
## Course legs and waypoints react to the mouse only when editing is enabled.
var editing_enabled := false
## Weather areas drawn (off on the cabin's Dreamer's Map, Iteration 17).
var show_weather := true
## The next turn of the course being sailed (a ring), or Vector2.INF.
var next_waypoint_geo := Vector2.INF

var _geo_bounds := Rect2()
var _map_bounds := Rect2()
var _labels: Array[Dictionary] = []
## Weather events drawn on the chart (projected outlines), for weather_time.
var _weather_shapes: Array[Dictionary] = []
## Game time the weather overlay shows (follows the game clock in steps).
var weather_time := -1.0
var _hovered_port_id: StringName
## Shown on the chart (tests and the world map may switch them off).
var show_cruising_regions := true
## The region mark / named anchorage under the cursor, or &"".
var hovered_cruising_region: StringName
var hovered_anchorage: StringName
## Each region's outlines in map space (built once with the land).
var _cruising_outlines := {}
var _shown_anchorages: Array[Dictionary] = []
## Harbours with a marker in the current view, most important first, and the
## ones whose name is written (see _update_port_layout()).
var _shown_ports: Array[PortData] = []
var _labelled_ports := {}
var _port_layout_key := ""
var _press := Press.NONE
var _press_position := Vector2.ZERO
var _press_waypoint := -1
var _press_leg := -1
var _moved := false

## The world (Iteration 16): true when the world chart data is present.
var _has_world := false
## Map units for 360° of longitude.
var _world_width := 0.0
var _overlay_view_key := Vector3.INF
var _europe_layer: Node2D
## Detail regions of the world chart itself (New Zealand), over the world land.
var _world_detail_layer: Node2D
var _world_overview: Node2D
var _world_regional: Node2D
## The world land, projected once and kept for every chart opened later.
static var _world_cache := {}

@onready var camera: Camera2D = $Camera2D
@onready var _land: Node2D = $Land
@onready var _overlay: Node2D = $Overlay

## Wind arrows (above land) and tint (under the land fill).
var wind_layer := WindLayer.new()
var _wind_view_key := ""
## Anchorage highlights (0.105b): above the water, under the land fill, so the
## soft edges never paint the land.
var anchorage_layer := AnchorageLayer.new()
var _anchorage_view_key := ""


func _ready() -> void:
	projection = MapProjection.new(units_per_degree)
	catalog = PortCatalog.get_default()
	_overlay.draw.connect(_draw_overlay)
	_build_land()
	wind_layer.name = "Wind"
	wind_layer.map_view = self
	# On the wrapping world chart the wind runs on across the Date Line too.
	wind_layer.map_bounds = _map_bounds.grow_individual(_world_width, 0, _world_width, 0) if _has_world else _map_bounds
	add_child(wind_layer)
	move_child(wind_layer, _overlay.get_index())
	_land.add_child(wind_layer.tint)
	_land.move_child(wind_layer.tint, 1)  # just above the water, below the land fill
	anchorage_layer.name = "Anchorages"
	anchorage_layer.map_view = self
	anchorage_layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	anchorage_layer.visible = false
	_land.add_child(anchorage_layer)
	_land.move_child(anchorage_layer, 2)
	reset_view()
	# A window of another shape (stretch "expand") changes the smallest zoom.
	get_viewport().size_changed.connect(func() -> void:
		_set_zoom(camera.zoom.x)
		_clamp_camera())


# --- Public API ------------------------------------------------------------------------

func set_display(display: Dictionary) -> void:
	boat_port_id = display.get("boat_port_id", &"")
	selected_port_id = display.get("selected_port_id", &"")
	destination_port_id = display.get("destination_port_id", &"")
	vessel_geo = display.get("vessel_geo", Vector2.INF)
	travelled_path = display.get("travelled_path", PackedVector2Array())
	active_path = display.get("active_path", PackedVector2Array())
	draft_legs = display.get("draft_legs", [] as Array[Dictionary])
	draft_is_proposal = display.get("draft_is_proposal", false)
	waypoints = display.get("waypoints", [] as Array[Vector2])
	anchorages = display.get("anchorages", [] as Array[bool])
	anchorage_magic = display.get("anchorage_magic", [] as Array[bool])
	invalid_waypoints = display.get("invalid_waypoints", PackedInt32Array())
	selected_waypoint = display.get("selected_waypoint", -1)
	editing_enabled = display.get("editing_enabled", false)
	next_waypoint_geo = display.get("next_waypoint_geo", Vector2.INF)
	visited_pins = display.get("visited_pins", [] as Array[StringName])
	_overlay.queue_redraw()


# --- Visited harbours (Cozy Polish, the Dreamer's Map) -----------------------------------
# A small red pin for each harbour the Captain has visited (the Captain's Log),
# whatever the zoom. Pins closer than PIN_CLUSTER_PX on screen become one pin
# with a number; hovering a pin names its harbour(s).

const PIN_RED := Color("#C0392B")
const PIN_RED_DARK := Color("#7A1F16")
const PIN_CLUSTER_PX := 16.0
var visited_pins: Array[StringName] = []
var _hovered_pin := -1


## The pins as drawn now: [{"geo", "ids": [port ids], "screen"}], nearby pins
## merged (most visited part of the map stays tidy at broad zoom).
func get_pin_groups() -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	for id in visited_pins:
		var port := catalog.get_port(id)
		if port == null:
			continue
		var at := map_to_screen(_near_view(projection.geo_to_map(port.get_geo_position())))
		var joined := false
		for g in groups:
			if (g.screen as Vector2).distance_to(at) < PIN_CLUSTER_PX:
				(g.ids as Array).append(id)
				joined = true
				break
		if not joined:
			groups.append({"geo": port.get_geo_position(), "ids": [id], "screen": at})
	return groups


func _draw_pins(s: float) -> void:
	var groups := get_pin_groups()
	for i in groups.size():
		var g: Dictionary = groups[i]
		var tip := _near_view(projection.geo_to_map(g.geo))
		var head := tip + Vector2(0.0, -15.0) * s
		_overlay.draw_line(tip, head, PIN_RED_DARK, 2.0 * s, true)
		_overlay.draw_circle(head, 6.0 * s, PIN_RED_DARK, true, -1.0, true)
		_overlay.draw_circle(head, 4.8 * s, PIN_RED, true, -1.0, true)
		_overlay.draw_circle(head + Vector2(-1.6, -1.6) * s, 1.4 * s, Color(1, 1, 1, 0.55), true, -1.0, true)
		var count := (g.ids as Array).size()
		if count > 1:
			_draw_text(str(count), head + Vector2(8.0, 4.0) * s, 13.0 * s, PIN_RED_DARK, false, true)
		if i == _hovered_pin:
			var names := PackedStringArray()
			for id: StringName in g.ids:
				names.append(catalog.get_port(id).display_name)
			var text := ", ".join(names) if names.size() <= 4 else Loc.t("%s and %d more") % [", ".join(names.slice(0, 3)), names.size() - 3]
			_draw_text(text, head + Vector2(10.0, -10.0) * s, 15.0 * s, PORT_FILL, false, true)


func _pin_at(screen_point: Vector2) -> int:
	var groups := get_pin_groups()
	for i in groups.size():
		var head: Vector2 = (groups[i].screen as Vector2) + Vector2(0.0, -15.0)
		if head.distance_to(screen_point) <= 9.0 or (groups[i].screen as Vector2).distance_to(screen_point) <= 6.0:
			return i
	return -1


## The smallest zoom allowed now (the whole chart, never past its data).
func get_min_zoom() -> float:
	var current := camera.zoom.x
	_set_zoom(0.0)
	var smallest := camera.zoom.x
	_set_zoom(current)
	return smallest


## Shows the whole region in the visible chart area.
func reset_view() -> void:
	var free := _free_view_size()
	_set_zoom(minf(free.x / _map_bounds.size.x, free.y / _map_bounds.size.y) * 0.96)
	camera.position = _map_bounds.get_center()
	_clamp_camera()


func center_on_geo(geo: Vector2, zoom := -1.0) -> void:
	if zoom > 0.0:
		_set_zoom(zoom)
	camera.position = projection.geo_to_map(geo)
	_clamp_camera()
	_overlay.queue_redraw()


## Zooms so that all `points` are visible with some margin.
func frame_geo_points(points: PackedVector2Array) -> void:
	if points.is_empty():
		return
	if _has_world:
		points = GeoMath.unwrap_path(points)  # a course across the Date Line stays together
	var rect := Rect2(projection.geo_to_map(points[0]), Vector2.ZERO)
	for p in points:
		rect = rect.expand(projection.geo_to_map(p))
	var free := _free_view_size() * 0.8
	var zoom := minf(free.x / maxf(rect.size.x, 1.0), free.y / maxf(rect.size.y, 1.0))
	_set_zoom(minf(zoom, 2.0))
	camera.position = rect.get_center()
	_clamp_camera()


func zoom_by(factor: float, screen_point: Variant = null) -> void:
	var anchor: Vector2 = screen_point if screen_point is Vector2 else _view_center()
	var before := screen_to_map(anchor)
	_set_zoom(camera.zoom.x * factor)
	camera.position += before - screen_to_map(anchor)
	_clamp_camera()


func get_zoom() -> float:
	return camera.zoom.x


func screen_to_map(screen_point: Vector2) -> Vector2:
	return camera.position + (screen_point - _view_center()) / camera.zoom.x


func map_to_screen(map_point: Vector2) -> Vector2:
	return (map_point - camera.position) * camera.zoom.x + _view_center()


func screen_to_geo(screen_point: Vector2) -> Vector2:
	var geo := projection.map_to_geo(screen_to_map(screen_point))
	return GeoMath.normalize(geo) if _has_world else geo


## A position on screen; on the world chart in the copy nearest the view's centre.
func geo_to_screen(geo: Vector2) -> Vector2:
	return map_to_screen(_near_view(projection.geo_to_map(geo)))


## `map_point` shifted by whole world-widths to the copy nearest the camera.
func _near_view(map_point: Vector2) -> Vector2:
	if _has_world and camera:
		map_point.x += roundf((camera.position.x - map_point.x) / _world_width) * _world_width
	return map_point


## A geographic path in map space, continuous across the Date Line and in the
## copy nearest the camera (for drawing and picking).
func _path_to_map(path: PackedVector2Array) -> PackedVector2Array:
	var points := projection.geo_polygon_to_map(GeoMath.unwrap_path(path) if _has_world else path)
	if _has_world and not points.is_empty():
		var shift := _near_view(points[0]).x - points[0].x
		if shift != 0.0:
			points = _shifted(points, shift)
	return points


## Every copy of a geographic path (as _path_to_map()) that reaches into the
## view. A long route spans much of a world width, so the copy chosen by its
## first point alone can lie outside the view while another copy of the same
## route is in it (Iteration 18: routes vanished while panning). Off the world
## chart there is only the one copy.
func _path_copies(path: PackedVector2Array) -> Array[PackedVector2Array]:
	var points := _path_to_map(path)
	var copies: Array[PackedVector2Array] = []
	if not _has_world or points.size() < 2:
		if not points.is_empty():
			copies.append(points)
		return copies
	var low := INF
	var high := -INF
	for p in points:
		low = minf(low, p.x)
		high = maxf(high, p.x)
	var margin := 40.0 / maxf(get_zoom(), 1e-6)
	var view_low := screen_to_map(Vector2.ZERO).x - margin
	var view_high := screen_to_map(Vector2(get_viewport_rect().size.x, 0.0)).x + margin
	for k in range(-2, 3):
		var dx := k * _world_width
		if high + dx >= view_low and low + dx <= view_high:
			copies.append(points if k == 0 else _shifted(points, dx))
	return copies


func get_port_screen_position(port_id: StringName) -> Vector2:
	var port := catalog.get_port(port_id)
	return geo_to_screen(port.get_geo_position()) if port else Vector2.INF


## Port id under a screen position, or &"" if none is within reach. Only
## harbours with a marker can be clicked; the others are found by zooming in
## or with the chart's harbour search.
func pick_port(screen_point: Vector2) -> StringName:
	_update_port_layout()
	var best: StringName = &""
	var best_distance := PICK_RADIUS_PX
	for port in _shown_ports:
		var distance := geo_to_screen(port.get_geo_position()).distance_to(screen_point)
		if distance <= best_distance:
			best_distance = distance
			best = port.id
	return best


func pick_waypoint(screen_point: Vector2) -> int:
	var best := -1
	var best_distance := WAYPOINT_PICK_PX
	for i in waypoints.size():
		var distance := geo_to_screen(waypoints[i]).distance_to(screen_point)
		if distance <= best_distance:
			best_distance = distance
			best = i
	return best


## Leg index of the drawn course under a screen position, or -1.
func pick_route_leg(screen_point: Vector2) -> int:
	var best := -1
	var best_distance := ROUTE_PICK_PX
	for leg_index in draft_legs.size():
		for points in _path_copies(draft_legs[leg_index].path):
			for i in range(1, points.size()):
				var a := map_to_screen(points[i - 1])
				var b := map_to_screen(points[i])
				var closest := Geometry2D.get_closest_point_to_segment(screen_point, a, b)
				var distance := closest.distance_to(screen_point)
				if distance <= best_distance:
					best_distance = distance
					best = leg_index
	return best


## Called by WorldMap after inserting a waypoint on a route press, so the
## same mouse press continues as a drag of the new waypoint.
func begin_waypoint_drag(index: int) -> void:
	_press = Press.WAYPOINT
	_press_waypoint = index
	_moved = true


# --- Input -------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	var mouse_button := event as InputEventMouseButton
	if mouse_button:
		_handle_mouse_button(mouse_button)
		return
	var motion := event as InputEventMouseMotion
	if motion:
		_handle_mouse_motion(motion)
		return
	if event.is_action_pressed(&"map_zoom_in"):
		zoom_by(ZOOM_STEP)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"map_zoom_out"):
		zoom_by(1.0 / ZOOM_STEP)
		get_viewport().set_input_as_handled()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				zoom_by(ZOOM_STEP, event.position)
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				zoom_by(1.0 / ZOOM_STEP, event.position)
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_begin_left_press(event.position)
			else:
				_end_left_press(event.position)
		MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				var waypoint := pick_waypoint(event.position) if editing_enabled and event.button_index == MOUSE_BUTTON_RIGHT else -1
				_press = Press.REMOVE if waypoint >= 0 else Press.PAN
				_press_waypoint = waypoint
				_press_position = event.position
				_moved = false
			else:
				if _press == Press.REMOVE and not _moved:
					waypoint_remove_requested.emit(_press_waypoint)
				_press = Press.NONE
		_:
			return
	get_viewport().set_input_as_handled()


func _begin_left_press(position: Vector2) -> void:
	_press_position = position
	_moved = false
	_press = Press.PENDING
	if not editing_enabled:
		return
	var waypoint := pick_waypoint(position)
	if waypoint >= 0:
		_press = Press.WAYPOINT
		_press_waypoint = waypoint
		waypoint_pressed.emit(waypoint)
		return
	if pick_port(position).is_empty() and pick_anchorage(position).is_empty():
		var leg := pick_route_leg(position)
		if leg >= 0:
			_press = Press.ROUTE
			_press_leg = leg


func _end_left_press(position: Vector2) -> void:
	match _press:
		Press.WAYPOINT:
			if _moved:
				waypoint_released.emit(_press_waypoint, screen_to_geo(position))
		Press.PENDING, Press.ROUTE:
			var port := pick_port(position)
			var anchorage := pick_anchorage(position) if port.is_empty() else &""
			var region := pick_cruising_region(position) if port.is_empty() and anchorage.is_empty() else &""
			if not port.is_empty():
				port_clicked.emit(port)
			elif not anchorage.is_empty():
				anchorage_clicked.emit(anchorage)
			elif not region.is_empty():
				cruising_region_clicked.emit(region)
			else:
				map_clicked.emit(screen_to_geo(position))
	_press = Press.NONE


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _press != Press.NONE and not _moved and event.position.distance_to(_press_position) > CLICK_SLOP_PX:
		_moved = true
		if _press == Press.ROUTE:
			# Dragging the course line: a new waypoint where it was pressed,
			# dragged from there (route_pressed starts the waypoint drag).
			route_pressed.emit(_press_leg, screen_to_geo(_press_position))
		elif _press == Press.PENDING or _press == Press.REMOVE:
			_press = Press.PAN
	match _press:
		Press.PAN:
			camera.position -= event.relative / camera.zoom.x
			_clamp_camera()
			_overlay.queue_redraw()
		Press.WAYPOINT:
			if _moved:
				waypoint_dragged.emit(_press_waypoint, screen_to_geo(event.position))
	if not visited_pins.is_empty():
		var pin := _pin_at(event.position)
		if pin != _hovered_pin:
			_hovered_pin = pin
			_overlay.queue_redraw()
	var hovered := pick_port(event.position)
	if hovered != _hovered_port_id:
		_hovered_port_id = hovered
		_overlay.queue_redraw()
	var anchorage := pick_anchorage(event.position) if hovered.is_empty() else &""
	var region := pick_cruising_region(event.position) if hovered.is_empty() and anchorage.is_empty() else &""
	if anchorage != hovered_anchorage or region != hovered_cruising_region:
		hovered_anchorage = anchorage
		hovered_cruising_region = region
		_overlay.queue_redraw()
		cruising_hover_changed.emit()
	var map_point := screen_to_map(event.position)
	var inside := map_point.y >= _map_bounds.position.y and map_point.y <= _map_bounds.end.y if _has_world else _map_bounds.has_point(map_point)
	cursor_moved.emit(screen_to_geo(event.position) if inside else null)


func _process(delta: float) -> void:
	if GameSession.is_active() and show_weather:
		var shown := floorf(GameSession.get_game_time() / WEATHER_REFRESH_SECONDS) * WEATHER_REFRESH_SECONDS
		if weather_time < 0.0 or shown != weather_time:
			set_weather_time(shown)
	if wind_layer.visible:
		wind_layer.update_time(GameSession.get_game_time())
		var key := "%s|%s|%s" % [camera.position, camera.zoom.x, get_viewport_rect().size]
		if key != _wind_view_key:
			_wind_view_key = key
			wind_layer.refresh_view()
	if anchorage_layer.shown:
		var anchor_key := "%s|%s|%s" % [camera.position, camera.zoom.x, get_viewport_rect().size]
		if anchor_key != _anchorage_view_key:
			_anchorage_view_key = anchor_key
			anchorage_layer.refresh_view()
	_update_world_tiles()
	# Whatever moved the camera (dragging, keys, centring, the wrap at the
	# Date Line), the overlay's route copies follow the view.
	var view_key := Vector3(camera.position.x, camera.position.y, camera.zoom.x)
	if view_key != _overlay_view_key:
		_overlay_view_key = view_key
		_overlay.queue_redraw()
	var direction := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	# Typing in a text field (the harbour search) must not pan the chart.
	if direction != Vector2.ZERO and not get_viewport().gui_get_focus_owner() is LineEdit:
		camera.position += direction * keyboard_pan_speed * delta / camera.zoom.x
		_clamp_camera()
		_overlay.queue_redraw()


# --- Building ----------------------------------------------------------------------------

## The Dreamer's Map's illustrated colours (after 0.105b): green land, snowy
## far north and Antarctica, sandy deserts, a deeper sea. A screen-reading
## shader drawn over the land layer and under the overlay (labels, ports,
## routes), so only the colours change - never the coastlines, navigation or
## the working chart, which never calls this.
const DREAM_SHADER := preload("res://src/navigation/shaders/dream_world.gdshader")

var _dream_tint: Node2D


func set_dream_style(on: bool) -> void:
	if not on:
		if _dream_tint:
			_dream_tint.queue_free()
			_dream_tint = null
		return
	if _dream_tint:
		return
	_dream_tint = Node2D.new()
	_dream_tint.name = "DreamTint"
	add_child(_dream_tint)
	move_child(_dream_tint, _overlay.get_index())
	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_dream_tint.add_child(copy)
	var rect := ColorRect.new()
	rect.name = "Colours"
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Wider and taller than the chart: the land fill runs a little past its bounds.
	var area := _map_bounds.grow_individual(_world_width * 2.0, _map_bounds.size.y, _world_width * 2.0, _map_bounds.size.y)
	rect.position = area.position
	rect.size = area.size
	var material := ShaderMaterial.new()
	material.shader = DREAM_SHADER
	material.set_shader_parameter(&"rect_origin", area.position)
	material.set_shader_parameter(&"scale", projection.scale)
	material.set_shader_parameter(&"land_src", LAND)
	material.set_shader_parameter(&"islet_src", ISLET_COLOUR)
	material.set_shader_parameter(&"coast_src", COAST)
	material.set_shader_parameter(&"water_src", WATER)
	rect.material = material
	_dream_tint.add_child(rect)


func is_dream_style() -> bool:
	return _dream_tint != null


func _build_land() -> void:
	var data: Dictionary = land_data.data if land_data and land_data.data is Dictionary else {}
	var bounds: Dictionary = data.get("bounds", {"west": -10.0, "south": 50.0, "east": 20.0, "north": 60.0})
	var world_meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(WORLD_META)) if FileAccess.file_exists(WORLD_META) else null
	_has_world = world_meta is Dictionary
	if _has_world:
		bounds = world_meta.bounds
	_geo_bounds = Rect2(bounds.west, bounds.south, bounds.east - bounds.west, bounds.north - bounds.south)
	var top_left := projection.geo_to_map(Vector2(bounds.west, bounds.north))
	var bottom_right := projection.geo_to_map(Vector2(bounds.east, bounds.south))
	_map_bounds = Rect2(top_left, bottom_right - top_left)
	_world_width = 360.0 * units_per_degree

	var water := Polygon2D.new()
	water.name = "Water"
	water.color = WATER
	# On the world chart the water runs one world-width further each side (wrapping).
	var water_rect := _map_bounds.grow_individual(_world_width, 0, _world_width, 0) if _has_world else _map_bounds
	water.polygon = PackedVector2Array([water_rect.position, Vector2(water_rect.end.x, water_rect.position.y),
		water_rect.end, Vector2(water_rect.position.x, water_rect.end.y)])
	_land.add_child(water)

	if _has_world:
		_world_overview = Node2D.new()
		_world_overview.name = "WorldOverview"
		_land.add_child(_world_overview)
		_build_world_layer(_world_overview, "overview")

	# Europe's own chart: drawn from EUROPE_DETAIL_PX on (always, without world data).
	_europe_layer = Node2D.new()
	_europe_layer.name = "Europe"
	_land.add_child(_europe_layer)
	_world_detail_layer = Node2D.new()
	_world_detail_layer.name = "WorldRegions"
	_land.add_child(_world_detail_layer)

	# Detail regions (Iteration 14): inside them the base land is cut away and
	# the region draws its own (see _build_regions()).
	_load_region_rects()

	# Projected, clipped and checked once, then kept (static) for every later
	# chart opening (Iteration 16).
	var europe := _europe_shapes(data)
	for piece: PackedVector2Array in europe.fill:
		var polygon := Polygon2D.new()
		polygon.color = LAND
		polygon.polygon = piece
		_europe_layer.add_child(polygon)
	_add_coast_tiles(_europe_layer, europe.coast, "Coast")

	for label: Dictionary in data.get("labels", []):
		_labels.append({
			"text": label.get("text", ""),
			"position": projection.geo_to_map(Vector2(label.get("lon", 0.0), label.get("lat", 0.0))),
			"sea": label.get("kind", "") == "sea",
			"size": 22 if label.get("kind", "") != "sea" else 19,
			"min_px": EUROPE_LABEL_PX if _has_world else 0.0,
			"max_px": INF,
		})
	if _has_world:
		for label: Dictionary in _world_data().get("labels", []):
			var kind: String = label.get("kind", "")
			_labels.append({
				"text": label.get("text", ""),
				"position": projection.geo_to_map(Vector2(label.get("lon", 0.0), label.get("lat", 0.0))),
				"sea": kind == "sea" or kind == "island",  # island groups sit in the sea: the sea's lighter text
				"size": {"land": 20, "island": 15, "sea": 17}.get(kind, 16),
				"min_px": float(label.get("min_px_per_degree", 0.0)),
				"max_px": float(label.get("max_px_per_degree", INF)),
			})
	_build_regions()
	_project_cruising_regions()


## The world land, projected to map space once (static cache): per layer
## "fill" and "coast" (Array[PackedVector2Array]), "islets" and "labels".
func _world_data() -> Dictionary:
	if not _world_cache.is_empty() and is_equal_approx(float(_world_cache.get("scale", 0.0)), units_per_degree):
		return _world_cache
	var started := Time.get_ticks_msec()
	var prepared := load(WORLD_LAND_RES) as WorldLand if ResourceLoader.exists(WORLD_LAND_RES) else null
	if prepared and is_equal_approx(prepared.scale, units_per_degree):
		_world_cache = {"scale": units_per_degree, "labels": prepared.labels, "islets": prepared.islets,
			"overview": {"fill": prepared.overview_fill, "coast": prepared.overview_coast},
			"regional": {"fill": prepared.regional_fill, "coast": prepared.regional_coast}}
		SessionLog.write("global_chart_loaded", {"ms": Time.get_ticks_msec() - started, "overview_rings": prepared.overview_fill.size(),
			"regional_rings": prepared.regional_fill.size(), "islets": prepared.islets.size()})
		return _world_cache
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(WORLD_LAND)) if FileAccess.file_exists(WORLD_LAND) else null
	if not raw is Dictionary:
		return {}
	var cache := {"scale": units_per_degree, "labels": raw.get("labels", [])}
	for level in ["overview", "regional"]:
		var fill: Array[PackedVector2Array] = []
		for ring: Array in raw.get(level, {}).get("fill_tiles", []):
			fill.append(_project_ring(ring))
		var coast: Array[PackedVector2Array] = []
		for line: Array in raw.get(level, {}).get("coast", []):
			coast.append(_project_ring(line))
		cache[level] = {"fill": fill, "coast": coast}
	var islets := PackedVector2Array()
	for p: Array in raw.get("islets", []):
		islets.append(projection.geo_to_map(Vector2(p[0], p[1])))
	cache["islets"] = islets
	_world_cache = cache
	return cache


## One world land layer, with copies one world-width over near ±180°. Land
## is grouped into square tiles, each one canvas item that draws its fill,
## coast and islets; a tile is shown (and so triangulated, once) only when it
## comes into view (_update_world_tiles()), so opening the chart stays quick.
## The world wraps east-west: the layer is drawn in three copies one
## world-width apart (west, main, east), which share the same tile data. A
## tile is shown in a copy only when that copy of it is in view, so whatever
## the camera position and zoom, every visible longitude has its land
## (Iteration 17: before, only land within 40° of ±180° was copied, and the
## whole-world view, ~315° wide, showed rectangular gaps toward Asia,
## Australia and the Americas).
func _build_world_layer(parent: Node2D, level: String) -> void:
	var tiles := _world_tiles(level)
	for copy_index in 3:
		var copy := Node2D.new()
		copy.name = ["West", "Main", "East"][copy_index]
		copy.position.x = float(copy_index - 1) * _world_width
		parent.add_child(copy)
		for content: Dictionary in tiles:
			var tile := Node2D.new()
			tile.visible = false
			tile.set_meta(&"rect", content.rect)
			tile.set_meta(&"content", content)
			tile.draw.connect(_draw_world_tile.bind(tile, content))
			var islets: PackedVector2Array = content.islets
			if not islets.is_empty():
				# Dots sized for the screen: their own item, redrawn on zoom without
				# touching the land's triangulation.
				var dots := Node2D.new()
				dots.name = "Islets"
				dots.draw.connect(_draw_islets.bind(dots, islets))
				tile.add_child(dots)
			copy.add_child(tile)
	_world_tile_key = ""


## The tiles of a world layer (cached with the world data):
## [{"rect", "points", "indices", "segments", "islets"}], one world wide.
## Iteration 17: no wrap copies are baked into the tiles any more; the layer
## is drawn three times, one world-width apart (see _build_world_layer()).
func _world_tiles(level: String) -> Array:
	var data := _world_data()
	if not data.has(level):
		return []
	var cache_key := "tiles_" + level
	if data.has(cache_key):
		return data[cache_key]
	# Each tile is drawn in two calls (Iteration 16): its land as one indexed
	# triangle array, its coast as one batch of line segments.
	var tiles := {}
	for ring: PackedVector2Array in data[level].fill:
		if ring.size() < 3 or absf(MapView._ring_area(ring)) < 0.05:
			continue  # a sliver: nothing to draw
		var triangles := Geometry2D.triangulate_polygon(ring)
		if triangles.is_empty():
			continue  # degenerate: cannot be filled
		var tile := _tile_of(tiles, MapView._bounds_of(ring))
		var base: int = tile.points.size()
		tile.points.append_array(ring)
		for index in triangles:
			tile.indices.append(base + index)
	for line: PackedVector2Array in data[level].coast:
		var segments: PackedVector2Array = _tile_of(tiles, MapView._bounds_of(line)).segments
		for i in range(1, line.size()):
			segments.append(line[i - 1])
			segments.append(line[i])
	if level == "regional":
		for p in data.islets:
			_tile_of(tiles, Rect2(p, Vector2.ZERO)).islets.append(p)
	data[cache_key] = tiles.values()
	return data[cache_key]


## A fill ring as pieces the renderer can triangulate (Regions and Harbours
## 2026): the ring itself, or, when the triangulation rejects it (a long,
## nearly self-touching coast), its quarters clipped out of it, up to three
## times; slivers are left out.
static func _drawable_pieces(points: PackedVector2Array, depth := 0) -> Array[PackedVector2Array]:
	var pieces: Array[PackedVector2Array] = []
	if points.size() < 3 or absf(_ring_area(points)) < 0.05:
		return pieces
	if not Geometry2D.triangulate_polygon(points).is_empty():
		pieces.append(points)
		return pieces
	if depth >= 3:
		return pieces
	var box := _bounds_of(points)
	var half := box.size / 2.0
	for k in 4:
		var quarter := Rect2(box.position + Vector2(k % 2, k / 2) * half, half)
		var cut := PackedVector2Array([quarter.position, Vector2(quarter.end.x, quarter.position.y), quarter.end, Vector2(quarter.position.x, quarter.end.y)])
		for clipped in Geometry2D.intersect_polygons(points, cut):
			if not Geometry2D.is_polygon_clockwise(clipped):
				pieces.append_array(_drawable_pieces(clipped, depth + 1))
	return pieces


## False for slivers and degenerate rings: nothing visible to draw, and the
## renderer cannot triangulate them (it would report an error every frame).
static func _drawable(ring: PackedVector2Array) -> bool:
	return ring.size() >= 3 and absf(_ring_area(ring)) >= 0.05 and not Geometry2D.triangulate_polygon(ring).is_empty()


## Signed area of a ring (map units²).
static func _ring_area(points: PackedVector2Array) -> float:
	var area := 0.0
	var n := points.size()
	for i in n:
		var a := points[i]
		var b := points[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	return area * 0.5


static func _shifted(points: PackedVector2Array, dx: float) -> PackedVector2Array:
	var result := points.duplicate()
	for i in result.size():
		result[i].x += dx
	return result


## World tiles are WORLD_TILE_DEG on a side (map units: degrees × units_per_degree).
const WORLD_TILE_DEG := 10.0


func _tile_of(tiles: Dictionary, box: Rect2) -> Dictionary:
	var size := WORLD_TILE_DEG * units_per_degree
	var key := Vector2i((box.get_center() / size).floor())
	if not tiles.has(key):
		tiles[key] = {"points": PackedVector2Array(), "indices": PackedInt32Array(), "segments": PackedVector2Array(),
			"islets": PackedVector2Array(), "rect": box}
	var tile: Dictionary = tiles[key]
	tile.rect = (tile.rect as Rect2).merge(box)  # the drawn extent can reach past the square
	return tile


func _draw_world_tile(tile: Node2D, content: Dictionary) -> void:
	if not content.indices.is_empty():
		RenderingServer.canvas_item_add_triangle_array(tile.get_canvas_item(), content.indices, content.points,
			PackedColorArray([LAND]))
	if not content.segments.is_empty():
		tile.draw_multiline(content.segments, COAST, -1.0)


## Islet dots, a constant size on screen, as one triangle array per tile.
func _draw_islets(dots: Node2D, islets: PackedVector2Array) -> void:
	var r := 1.6 / maxf(camera.zoom.x, 0.0001)
	var points := PackedVector2Array()
	points.resize(islets.size() * 4)
	var indices := PackedInt32Array()
	indices.resize(islets.size() * 6)
	for i in islets.size():
		var q := islets[i]
		points[i * 4] = q + Vector2(-r, -r)
		points[i * 4 + 1] = q + Vector2(r, -r)
		points[i * 4 + 2] = q + Vector2(r, r)
		points[i * 4 + 3] = q + Vector2(-r, r)
		for k in 6:
			indices[i * 6 + k] = i * 4 + [0, 1, 2, 0, 2, 3][k]
	if not islets.is_empty():
		RenderingServer.canvas_item_add_triangle_array(dots.get_canvas_item(), indices, points, PackedColorArray([ISLET_COLOUR]))


var _world_tile_key := ""
var _islet_zoom := 0.0


## Shows the world tiles near the view and hides the rest (cheap; on view change).
func _update_world_tiles() -> void:
	if not _has_world or camera == null:
		return
	var view := get_viewport_rect().size
	var key := "%s|%s|%s|%s" % [camera.position.snapped(Vector2.ONE * 50.0), snappedf(camera.zoom.x, 0.0001), view,
		_world_regional != null]
	if key == _world_tile_key:
		return
	var zoomed := not _world_tile_key.contains("|%s|" % snappedf(camera.zoom.x, 0.0001))
	_world_tile_key = key
	var half := view / camera.zoom.x * 0.5
	var area := Rect2(camera.position - half - Vector2(occluded_right_px, 0) / camera.zoom.x, half * 2.0 + Vector2(occluded_right_px, 0) / camera.zoom.x)
	area = area.grow(WORLD_TILE_DEG * units_per_degree * 0.5)
	var redraw_islets := zoomed and absf(camera.zoom.x / maxf(_islet_zoom, 1e-9) - 1.0) > 0.15
	for layer: Node2D in [_world_overview, _world_regional]:
		if layer == null or not layer.visible:
			continue
		for copy: Node2D in layer.get_children():
			var shifted := Rect2(area.position - copy.position, area.size)  # the view in this copy's frame
			for tile: Node2D in copy.get_children():
				var rect: Rect2 = tile.get_meta(&"rect")
				var show := rect.grow(1.0).intersects(shifted)
				if show != tile.visible:
					tile.visible = show
				# Islets are sized for the screen: redraw the visible ones once the
				# zoom has changed enough to see (15 %).
				if redraw_islets and layer == _world_regional and show and tile.get_child_count() > 0:
					(tile.get_child(0) as Node2D).queue_redraw()
	if redraw_islets:
		_islet_zoom = camera.zoom.x


## Europe's land as drawn: fill pieces outside the detail regions and the
## coastline tiles, built once per scale (static cache).
static var _europe_cache := {}


func _europe_shapes(data: Dictionary) -> Dictionary:
	if is_equal_approx(float(_europe_cache.get("scale", 0.0)), units_per_degree):
		return _europe_cache
	var fill: Array[PackedVector2Array] = []
	# Land fill: polygons pre-clipped into tiles by the data builder.
	for ring: Array in data.get("fill_tiles", data.get("polygons", [])):
		for piece in _outside_regions(_project_ring(ring)):
			if MapView._drawable(piece):
				fill.append(piece)
	# Coastlines: drawn once as hairlines (constant 1 px at any zoom), split
	# into spatial tiles so the renderer can skip tiles outside the view.
	var tiles := {}
	for ring: Array in data.get("polygons", []):
		var points := _project_ring(ring)
		points.append(points[0])
		for line in _lines_outside_regions(points):
			_add_coast_runs(tiles, line)
	_europe_cache = {"scale": units_per_degree, "fill": fill, "coast": tiles}
	return _europe_cache


## A region's land as drawn, per level ({"overview": {"fill", "coast"},
## "detail": …, "labels"}), built once per scale (static cache).
static var _region_cache := {}


func _region_shapes(region: Dictionary) -> Dictionary:
	var key := "%s|%s" % [region.id, units_per_degree]
	if _region_cache.has(key):
		return _region_cache[key]
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(region.folder).path_join("land.json")))
	if not data is Dictionary:
		return {}
	var shapes := {"labels": data.get("labels", [])}
	for level in ["overview", "detail"]:
		var fill: Array[PackedVector2Array] = []
		for ring: Array in data.get(level, {}).get("fill_tiles", []):
			fill.append_array(MapView._drawable_pieces(_project_ring(ring)))
		var tiles := {}
		for line: Array in data.get(level, {}).get("coast", []):
			_add_coast_runs(tiles, _project_ring(line))
		shapes[level] = {"fill": fill, "coast": tiles}
	_region_cache[key] = shapes
	return shapes


func _add_coast_runs(tiles: Dictionary, points: PackedVector2Array) -> void:
	var start := 0
	while start < points.size() - 1:
		var end := mini(start + COAST_RUN_POINTS, points.size() - 1)
		var run := points.slice(start, end + 1)
		var key := Vector2i((run[0] / COAST_TILE_UNITS).floor())
		if not tiles.has(key):
			tiles[key] = [] as Array[PackedVector2Array]
		tiles[key].append(run)
		start = end


func _add_coast_tiles(parent: Node, tiles: Dictionary, prefix: String) -> void:
	for key: Vector2i in tiles:
		var tile := Node2D.new()
		tile.name = "%s_%d_%d" % [prefix, key.x, key.y]
		var runs: Array[PackedVector2Array] = tiles[key]
		tile.draw.connect(func() -> void:
			for run in runs:
				tile.draw_polyline(run, COAST, -1.0))
		parent.add_child(tile)


# --- Detail regions (Iteration 14) ------------------------------------------------------

## Regions with their own chart data: {"id", "rect" (map), "folder", "detail_px"}.
var _regions: Array[Dictionary] = []
## Each region's two layers (overview, detail), shown by zoom.
var _region_layers: Array[Dictionary] = []


func _load_region_rects() -> void:
	_regions.clear()
	if not FileAccess.file_exists(NavGrid.REGIONS_INDEX):
		return
	var index: Variant = JSON.parse_string(FileAccess.get_file_as_string(NavGrid.REGIONS_INDEX))
	if not index is Dictionary:
		return
	for entry: Dictionary in index.get("regions", []):
		var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(entry.folder).path_join("region.json")))
		if not meta is Dictionary:
			continue
		var top_left := projection.geo_to_map(Vector2(meta.bounds.west, meta.bounds.north))
		var bottom_right := projection.geo_to_map(Vector2(meta.bounds.east, meta.bounds.south))
		_regions.append({"id": String(meta.id), "name": String(meta.get("name", meta.id)), "folder": String(entry.folder),
			"rect": Rect2(top_left, bottom_right - top_left), "detail_px": float(meta.get("detail_from_px_per_degree", 140.0)),
			"parent": String(entry.get("parent", "europe"))})


## The parts of a base land polygon outside every region.
func _outside_regions(points: PackedVector2Array) -> Array[PackedVector2Array]:
	var pieces: Array[PackedVector2Array] = [points]
	for region in _regions:
		var rect: Rect2 = region.rect
		var next: Array[PackedVector2Array] = []
		for piece in pieces:
			if not MapView._bounds_of(piece).intersects(rect):
				next.append(piece)
				continue
			var cut := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
			for clipped in Geometry2D.clip_polygons(piece, cut):
				if not Geometry2D.is_polygon_clockwise(clipped) and clipped.size() >= 3:
					next.append(clipped)
		pieces = next
	return pieces


## The parts of a base coastline outside every region.
func _lines_outside_regions(points: PackedVector2Array) -> Array[PackedVector2Array]:
	var lines: Array[PackedVector2Array] = []
	var current := PackedVector2Array()
	for p in points:
		var inside := false
		for region in _regions:
			if (region.rect as Rect2).has_point(p):
				inside = true
		if inside:
			if current.size() >= 2:
				lines.append(current)
			current = PackedVector2Array()
		else:
			current.append(p)
	if current.size() >= 2:
		lines.append(current)
	return lines


func _build_regions() -> void:
	_region_layers.clear()
	for region in _regions:
		var data := _region_shapes(region)
		if data.is_empty():
			continue
		var layers := {"detail_px": region.detail_px}
		var on_world: bool = region.parent == "world"
		for level in ["overview", "detail"]:
			var layer := Node2D.new()
			layer.name = "Region_%s_%s" % [region.id, level]
			(_world_detail_layer if on_world else _europe_layer).add_child(layer)
			if on_world:
				# The world's own (coarser) land lies under a world region: its
				# water is painted over it first, so only the region's land shows
				# (Regions and Harbours 2026). A copy one world-width west keeps it
				# in view across the Date Line.
				_add_world_region_level(layer, region.rect, data[level])
				layers[level] = layer
				continue
			for points: PackedVector2Array in data[level].fill:
				var polygon := Polygon2D.new()
				polygon.color = LAND
				polygon.polygon = points
				layer.add_child(polygon)
			_add_coast_tiles(layer, data[level].coast, "Coast")
			layers[level] = layer
		_region_layers.append(layers)
		for label: Dictionary in data.labels:
			var kind: String = label.get("kind", "")
			_labels.append({
				"text": label.get("text", ""),
				"position": projection.geo_to_map(Vector2(label.get("lon", 0.0), label.get("lat", 0.0))),
				"sea": kind == "sea",
				"size": {"land": 19, "island": 15, "sea": 16}.get(kind, 16),
				"min_px": float(label.get("min_px_per_degree", 90.0)),
				"max_px": INF,
				"region": true,
			})
	# A base chart name that a region also places (the Øresund, the Great
	# Belt…) is shown once: by the region, at its more exact position, and
	# as early as the base chart showed it.
	var base_min := {}
	for label in _labels:
		if not label.get("region", false):
			base_min[label.text] = float(label.min_px)
	var region_texts := {}
	for label in _labels:
		if label.get("region", false):
			region_texts[label.text] = true
			if base_min.has(label.text):
				label.min_px = minf(float(label.min_px), float(base_min[label.text]))
	_labels = _labels.filter(func(l: Dictionary) -> bool: return l.get("region", false) or not region_texts.has(l.text))
	_update_region_detail()


func _add_world_region_level(layer: Node2D, rect: Rect2, shapes: Dictionary) -> void:
	for copy_index in 2:
		var copy := Node2D.new()
		copy.name = ["Main", "West"][copy_index]
		copy.position.x = -_world_width * copy_index
		layer.add_child(copy)
		var water := Polygon2D.new()
		water.color = WATER
		water.polygon = PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
		copy.add_child(water)
		for points: PackedVector2Array in shapes.fill:
			var polygon := Polygon2D.new()
			polygon.color = LAND
			polygon.polygon = points
			copy.add_child(polygon)
		_add_coast_tiles(copy, shapes.coast, "Coast")


## Shows each region's detailed layer once the chart is zoomed in far enough,
## its overview layer otherwise.
func _update_region_detail() -> void:
	var px := get_px_per_degree() if camera else 0.0
	# The world chart (Iteration 16): coarse world land when zoomed out; Europe's
	# chart and the regional world land (built on first use) from EUROPE_DETAIL_PX.
	if _has_world:
		var regional := px >= EUROPE_DETAIL_PX
		_world_overview.visible = not regional
		_europe_layer.visible = regional
		if regional and _world_regional == null:
			_world_regional = Node2D.new()
			_world_regional.name = "WorldRegional"
			_land.add_child(_world_regional)
			_land.move_child(_world_regional, _europe_layer.get_index())
			_build_world_layer(_world_regional, "regional")
		if _world_regional:
			_world_regional.visible = regional
		_world_detail_layer.visible = regional
	for layers in _region_layers:
		var detail: bool = px >= float(layers.detail_px)
		(layers.detail as Node2D).visible = detail
		(layers.overview as Node2D).visible = not detail


## True when the world land layer now shown has a visible tile covering
## `map_point`, in whichever copy of the world that point lies (tests: the
## chart must never leave a gap where land is in view).
func is_world_land_drawn_at(map_point: Vector2) -> bool:
	for layer: Node2D in [_world_overview, _world_regional]:
		if layer == null or not layer.visible:
			continue
		for copy: Node2D in layer.get_children():
			var local := map_point - copy.position
			for tile: Node2D in copy.get_children():
				if tile.visible and (tile.get_meta(&"rect") as Rect2).has_point(local) \
						and MapView._triangles_contain(tile.get_meta(&"content"), local):
					return true
	return false


## True when `point` lies in one of the tile's filled triangles.
static func _triangles_contain(content: Dictionary, point: Vector2) -> bool:
	var points: PackedVector2Array = content.points
	var indices: PackedInt32Array = content.indices
	for i in range(0, indices.size(), 3):
		if Geometry2D.point_is_inside_triangle(point, points[indices[i]], points[indices[i + 1]], points[indices[i + 2]]):
			return true
	return false


## True when the coarse whole-world land is drawn (zoomed out), false when
## Europe's chart and the regional world land are (tests).
func is_world_overview_shown() -> bool:
	return _has_world and _world_overview.visible


func has_world() -> bool:
	return _has_world


## True when the detailed layer of region `id` is shown (tests).
func is_region_detail_shown(id: String) -> bool:
	for i in _region_layers.size():
		if _regions[i].id == id:
			return (_region_layers[i].detail as Node2D).visible
	return false


func get_region_ids() -> Array[String]:
	var ids: Array[String] = []
	for region in _regions:
		ids.append(String(region.id))
	return ids


func _project_ring(ring: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	points.resize(ring.size())
	for i in ring.size():
		points[i] = projection.geo_to_map(Vector2(ring[i][0], ring[i][1]))
	return points


## Projects the weather events existing at `time` (from the one weather
## model) to map space. Rebuilt only when the shown time changes.
func set_weather_time(time: float) -> void:
	if time == weather_time:
		return
	weather_time = time
	_weather_shapes.clear()
	var model := WeatherModel.get_default()
	for event in model.active_events(time, GameSession.get_wind_seed()):
		var outline := _project_geo(event.outline(time))
		if not Rect2(outline[0], Vector2.ZERO).merge(_bounds_of(outline)).intersects(_map_bounds):
			continue
		var shape := {"event": event, "outline": outline, "center": projection.geo_to_map(event.center_at(time)),
			"label": WeatherStyle.label(event, time), "strength": event.life_factor(time), "bounds": _bounds_of(outline)}
		if WeatherStyle.style(event.kind).core:
			shape["core"] = _project_geo(event.ring(time, 0.35 if event.kind != WeatherEvent.KIND_CYCLONE else 0.0, 32)) \
				if event.kind != WeatherEvent.KIND_CYCLONE else _project_geo(_circle(event.center_at(time), event.eye_radius_nm * 2.0))
		_weather_shapes.append(shape)
	_overlay.queue_redraw()


## The drawn weather shapes (tests): [{"event", "outline", "center", "label"}].
func get_weather_shapes() -> Array[Dictionary]:
	return _weather_shapes


func _project_geo(points: PackedVector2Array) -> PackedVector2Array:
	var projected := PackedVector2Array()
	for p in points:
		projected.append(projection.geo_to_map(p))
	return projected


static func _bounds_of(points: PackedVector2Array) -> Rect2:
	var box := Rect2(points[0], Vector2.ZERO)
	for p in points:
		box = box.expand(p)
	return box


static func _circle(center: Vector2, radius_nm: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 24:
		points.append(_destination(center, TAU * i / 24.0, radius_nm))
	return points


static func _destination(origin: Vector2, bearing: float, distance_nm: float) -> Vector2:
	var angular := distance_nm / GeoMath.EARTH_RADIUS_NM
	var lat1 := deg_to_rad(origin.y)
	var lon1 := deg_to_rad(origin.x)
	var lat2 := asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(bearing))
	var lon2 := lon1 + atan2(sin(bearing) * sin(angular) * cos(lat1), cos(angular) - sin(lat1) * sin(lat2))
	return Vector2(rad_to_deg(lon2), rad_to_deg(lat2))


func _set_zoom(value: float) -> void:
	# Never zoom out further than showing the whole region.
	var free := _free_view_size()
	var whole_region := minf(free.x / _map_bounds.size.x, free.y / _map_bounds.size.y) * 0.8
	if _has_world:
		# The wrapping world chart: at most one world wide, so no land and no
		# harbour is ever shown twice side by side; and never less than the
		# chart's height, so the view never shows past its north or south edge.
		whole_region = maxf(free.x / _world_width, free.y / _map_bounds.size.y)
	var zoom := clampf(value, maxf(min_zoom, whole_region), max_zoom)
	camera.zoom = Vector2(zoom, zoom)
	_update_region_detail()
	# Shift the camera so camera.position appears at the centre of the free area.
	camera.offset = Vector2(occluded_right_px / 2.0, 0.0) / zoom
	_overlay.queue_redraw()


func _free_view_size() -> Vector2:
	var view := get_viewport_rect().size
	return Vector2(maxf(view.x - occluded_right_px, 1.0), view.y)


func _view_center() -> Vector2:
	return _free_view_size() / 2.0


func _clamp_camera() -> void:
	if _has_world:
		# East-west the world wraps: the camera stays in the main copy.
		camera.position.x = fposmod(camera.position.x - _map_bounds.position.x, _world_width) + _map_bounds.position.x
		# North-south the view stays on the chart: its edges, not its centre, stop at the data's edge.
		var half := _free_view_size().y / 2.0 / camera.zoom.y
		var top := _map_bounds.position.y + half
		var bottom := _map_bounds.end.y - half
		camera.position.y = clampf(camera.position.y, top, bottom) if top <= bottom else _map_bounds.get_center().y
		return
	camera.position = camera.position.clamp(_map_bounds.position, _map_bounds.end)


# --- Harbour markers and labels -----------------------------------------------------------

## The geographic area (x = longitude, y = latitude) currently in view.
## On the world chart the rectangle is continuous: across the Date Line it
## reaches past ±180° (its centre is always within ±180°).
func get_visible_geo_rect() -> Rect2:
	var free := _free_view_size()
	var a := projection.map_to_geo(screen_to_map(Vector2.ZERO))
	var b := projection.map_to_geo(screen_to_map(free))
	var rect := Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (a - b).abs())
	if _has_world:
		var center_x := rect.get_center().x
		rect.position.x += GeoMath.normalize_lon(center_x) - center_x
	return rect


## Screen pixels per degree of longitude at the current zoom.
func get_px_per_degree() -> float:
	return units_per_degree * camera.zoom.x


## Ids of the harbours with a marker in the current view.
func get_shown_port_ids() -> Array[StringName]:
	_update_port_layout()
	var ids: Array[StringName] = []
	for port in _shown_ports:
		ids.append(port.id)
	return ids


## Ids of the harbours whose name is written in the current view.
func get_labelled_port_ids() -> Array[StringName]:
	_update_port_layout()
	var ids: Array[StringName] = []
	for id: StringName in _labelled_ports:
		ids.append(id)
	return ids


## Screen rectangles of the written harbour names (for tests).
func get_port_label_rects() -> Array[Rect2]:
	_update_port_layout()
	var rects: Array[Rect2] = []
	for id: StringName in _labelled_ports:
		rects.append(_labelled_ports[id])
	return rects


## Which harbours get a marker and a label in the current view. Only the
## harbours in view are considered (PortCatalog.ports_in_rect). A harbour
## has a marker when the zoom shows its importance, or when it is the
## selected, destination or current harbour. Labels are placed in order of
## importance and skipped where they would overlap a label or marker already
## placed, so the chart never fills with overlapping names. Recomputed only
## when the view or the highlighted harbours change.
func _update_port_layout() -> void:
	var view := get_viewport_rect().size
	var key := "%s|%s|%s|%s|%s|%s|%d" % [camera.position, camera.zoom.x, view, selected_port_id, destination_port_id,
		boat_port_id, catalog.ports.size()]
	if key == _port_layout_key:
		return
	_port_layout_key = key
	var margin := 40.0 / get_px_per_degree()
	var area := get_visible_geo_rect().grow(margin)
	var px := get_px_per_degree()
	_shown_ports.clear()
	for port in _ports_in_view(area):
		var special := port.id == selected_port_id or port.id == destination_port_id or port.id == boat_port_id
		if special or px >= PORT_MARKER_PX_PER_DEGREE[clampi(port.importance, 1, 3)]:
			_shown_ports.append(port)
	_shown_ports.sort_custom(_port_priority_before)
	if _has_world and px < EUROPE_DETAIL_PX:
		# World zoom: a marker too close to a more important one is left out
		# (it appears when zooming in), so markers never sit on each other.
		var kept: Array[PortData] = []
		var spots: Array[Vector2] = []
		for port in _shown_ports:
			var at := geo_to_screen(port.get_geo_position())
			var special := port.id == selected_port_id or port.id == destination_port_id or port.id == boat_port_id
			var crowded := spots.any(func(q: Vector2) -> bool: return q.distance_to(at) < DECLUTTER_PX)
			if special or not crowded:
				kept.append(port)
				spots.append(at)
		_shown_ports = kept
	var markers: Array[Rect2] = []
	for port in _shown_ports:
		markers.append(Rect2(geo_to_screen(port.get_geo_position()) - Vector2(9, 9), Vector2(18, 18)))
	_labelled_ports.clear()
	var placed: Array[Rect2] = []
	var scale := PORT_LABEL_PX / 22.0
	for i in _shown_ports.size():
		var port := _shown_ports[i]
		var at := geo_to_screen(port.get_geo_position())
		var size := LABEL_FONT.get_string_size(port.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22) * scale
		# Right of the marker if there is room, otherwise left, above or below.
		for offset: Vector2 in [Vector2(14.0, -size.y * 0.5), Vector2(-14.0 - size.x, -size.y * 0.5),
				Vector2(-size.x * 0.5, -12.0 - size.y), Vector2(-size.x * 0.5, 12.0)]:
			var rect := Rect2(at + offset, size).grow(PORT_LABEL_GAP_PX / 2.0)
			if _is_label_space_free(rect, placed, markers, i):
				placed.append(rect)
				_labelled_ports[port.id] = rect
				break


## Harbours inside a geographic rectangle that may reach past ±180° (wrapping).
func _ports_in_view(area: Rect2) -> Array[PortData]:
	var found := catalog.ports_in_rect(area)
	if not _has_world:
		return found
	for shift in [-360.0, 360.0]:
		var other := Rect2(area.position + Vector2(shift, 0), area.size)
		if other.end.x > -180.0 and other.position.x < 180.0 and (area.position.x < -180.0 or area.end.x > 180.0):
			for port in catalog.ports_in_rect(other):
				if not port in found:
					found.append(port)
	return found


func _is_label_space_free(rect: Rect2, placed: Array[Rect2], markers: Array[Rect2], own_marker: int) -> bool:
	for other in placed:
		if rect.intersects(other):
			return false
	for j in markers.size():
		if j != own_marker and rect.intersects(markers[j]):
			return false
	return true


## Highlighted harbours first, then by importance, then by name.
func _port_priority_before(a: PortData, b: PortData) -> bool:
	var ra := _port_rank(a)
	var rb := _port_rank(b)
	if ra != rb:
		return ra < rb
	return a.display_name < b.display_name


func _port_rank(port: PortData) -> int:
	if port.id == selected_port_id or port.id == destination_port_id:
		return 0
	if port.id == boat_port_id:
		return 1
	return 1 + port.importance


# --- Drawing -----------------------------------------------------------------------------

func _draw_overlay() -> void:
	var s := 1.0 / camera.zoom.x  # map units per screen pixel
	_draw_graticule(s)
	if not _has_world:  # the world chart wraps: no edge east or west
		_overlay.draw_rect(_map_bounds, WATER_EDGE, false, 3.0 * s)
	var px := get_px_per_degree()
	for label in _labels:
		if px < float(label.min_px) or px > float(label.get("max_px", INF)):
			continue
		_draw_text(label.text, _near_view(label.position), float(label.size) * s, LABEL_SEA if label.sea else LABEL_COUNTRY, true)
	if show_weather:
		_draw_weather(s)
	_draw_canals(s)
	_draw_cruising_regions(s, px)
	_draw_courses(s)
	_update_port_layout()
	_draw_anchorages(s, px)
	for i in range(_shown_ports.size() - 1, -1, -1):  # most important drawn last (on top)
		_draw_port(_shown_ports[i], s, _labelled_ports.has(_shown_ports[i].id))
	_draw_waypoints(s)
	if not visited_pins.is_empty():
		_draw_pins(s)
	if next_waypoint_geo != Vector2.INF:
		var turn := _near_view(projection.geo_to_map(next_waypoint_geo))
		_overlay.draw_arc(turn, 11.0 * s, 0.0, TAU, 24, BRASS, 2.5 * s)
		_overlay.draw_arc(turn, 15.0 * s, 0.0, TAU, 24, Color(PORT_RIM, 0.7), 1.5 * s)
	if vessel_geo != Vector2.INF:
		var at := _near_view(projection.geo_to_map(vessel_geo))
		if not boat_port_id.is_empty():
			at += Vector2(-26, -26) * s
		_draw_boat(at, s, not boat_port_id.is_empty())


# --- Detailed Cruising Regions (Regions and Harbours 2026) ---------------------------------

func _project_cruising_regions() -> void:
	_cruising_outlines.clear()
	for region: Dictionary in CruisingRegions.get_default().regions:
		var rings: Array[PackedVector2Array] = []
		for outline: PackedVector2Array in region.outlines:
			var ring := _project_geo(outline)
			ring.append(ring[0])
			rings.append(ring)
		_cruising_outlines[region.id] = rings


## How strongly the regions' marks show at `px` (1 zoomed out, 0 from CRUISING_MARK_MAX_PX).
func cruising_mark_strength(px := -1.0) -> float:
	if not show_cruising_regions:
		return 0.0
	px = get_px_per_degree() if px < 0.0 else px
	return clampf((CRUISING_MARK_MAX_PX - px) / (CRUISING_MARK_MAX_PX * 0.35), 0.0, 1.0)


## The region whose mark is under a screen position, or &"".
func pick_cruising_region(screen_point: Vector2) -> StringName:
	if cruising_mark_strength() < 0.3:
		return &""
	for region: Dictionary in CruisingRegions.get_default().regions:
		var at := map_to_screen(_near_view(projection.geo_to_map(region.symbol)))
		var label_end := at + Vector2(22.0 + LABEL_FONT.get_string_size(Loc.t(region.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x * 0.7, 0)
		if at.distance_to(screen_point) <= CRUISING_PICK_PX or Rect2(at + Vector2(10, -11), label_end - at + Vector2(0, 22)).has_point(screen_point):
			return region.id
	return &""


## The named anchorage under a screen position (only those with a marker), or &"".
func pick_anchorage(screen_point: Vector2) -> StringName:
	var best: StringName = &""
	var best_distance := CRUISING_PICK_PX
	for record in _shown_anchorages:
		var distance := geo_to_screen(record.position).distance_to(screen_point)
		if distance <= best_distance:
			best_distance = distance
			best = record.id
	return best


func get_shown_anchorage_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for record in _shown_anchorages:
		ids.append(record.id)
	return ids


func _draw_cruising_regions(s: float, px: float) -> void:
	var strength := cruising_mark_strength(px)
	if strength <= 0.0:
		return
	var regions := CruisingRegions.get_default()
	for region: Dictionary in regions.regions:
		var hovered: bool = region.id == hovered_cruising_region
		var colour := Color(CRUISING_ACCENT, (0.75 if hovered else 0.5) * strength)
		for ring: PackedVector2Array in _cruising_outlines.get(region.id, []):
			var shift := _near_view(ring[0]) - ring[0]
			for i in range(1, ring.size()):
				_overlay.draw_dashed_line(ring[i - 1] + shift, ring[i] + shift, colour, 2.0 * s, 10.0 * s, true, true)
		var at := _near_view(projection.geo_to_map(region.symbol))
		MapView.draw_cruising_symbol(_overlay, at, s, strength, hovered)
		if px < CRUISING_NAME_MIN_PX and not hovered:
			continue
		_draw_text(Loc.t(region.name), at + Vector2(14.0, 5.0) * s, 15.0 * s, Color(PORT_FILL, 0.92 * strength), false, true)


## The Detailed Cruising Region symbol: a small brass ring around a four-point
## star (a chart's compass mark, quieter than a harbour's pin). Also drawn in
## the chart's legend.
static func draw_cruising_symbol(canvas: CanvasItem, at: Vector2, s: float, strength := 1.0, hovered := false) -> void:
	var r := 7.0 * s
	canvas.draw_circle(at, r + 2.0 * s, Color(PORT_RIM, 0.75 * strength), true, -1.0, true)
	canvas.draw_arc(at, r, 0.0, TAU, 24, Color(CRUISING_ACCENT, strength), (2.2 if hovered else 1.6) * s, true)
	var star := PackedVector2Array()
	for k in 8:
		var a := -PI / 2.0 + k * PI / 4.0
		star.append(at + Vector2(cos(a), sin(a)) * (r * 0.72 if k % 2 == 0 else r * 0.22))
	canvas.draw_colored_polygon(star, Color(CRUISING_ACCENT, strength))


func _draw_anchorages(s: float, px: float) -> void:
	_shown_anchorages.clear()
	if not show_cruising_regions or px < ANCHORAGE_MARKER_PX:
		return
	var area := get_visible_geo_rect().grow(40.0 / px)
	var placed: Array[Rect2] = []
	for id: StringName in _labelled_ports:
		placed.append(_labelled_ports[id])
	for record in CruisingRegions.get_default().anchorages_in_rect(area):
		_shown_anchorages.append(record)
		var at := _near_view(projection.geo_to_map(record.position))
		var hovered: bool = record.id == hovered_anchorage
		var r := 7.0 * s
		if hovered:
			_overlay.draw_circle(at, r + 5.0 * s, HOVER, false, 2.0 * s, true)
		_overlay.draw_circle(at, r, PORT_RIM, true, -1.0, true)
		var w := 1.4 * s
		var c := Color(CRUISING_ACCENT, 1.0)
		_overlay.draw_circle(at + Vector2(0, -3.8) * s, 1.3 * s, c, false, w, true)  # ring
		_overlay.draw_line(at + Vector2(0, -2.5) * s, at + Vector2(0, 4.2) * s, c, w, true)  # shank
		_overlay.draw_line(at + Vector2(-2.6, -1.4) * s, at + Vector2(2.6, -1.4) * s, c, w, true)  # stock
		_overlay.draw_arc(at + Vector2(0, 0.6) * s, 3.9 * s, deg_to_rad(20.0), deg_to_rad(160.0), 10, c, w, true)  # arms
		if px < ANCHORAGE_LABEL_PX and not hovered:
			continue
		var title := Loc.t(String(record.name))
		var size := LABEL_FONT.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22) * (15.0 / 22.0)
		var screen := map_to_screen(at)
		var rect := Rect2(screen + Vector2(11.0, -size.y * 0.5), size)
		if not hovered and placed.any(func(other: Rect2) -> bool: return other.intersects(rect)):
			continue
		placed.append(rect)
		_draw_text(title, at + Vector2(11.0, 5.0) * s, 15.0 * s, Color(PORT_FILL, 0.85), false, true)


func _draw_graticule(s: float) -> void:
	# Keep grid lines at least ~90 px apart.
	var degree_px := units_per_degree / s
	var step := 1
	for candidate in [1, 2, 5, 10, 20, 30]:
		step = candidate
		if candidate * degree_px >= 90.0:
			break
	# Longitudes in view (on the world chart, past ±180 too: wrapping).
	var view := get_visible_geo_rect() if _has_world else _geo_bounds
	var lon_from := ceili(view.position.x / step) * step if _has_world else ceili(_geo_bounds.position.x / step) * step
	var lon_to := view.end.x if _has_world else _geo_bounds.end.x
	var lon := lon_from
	while lon <= lon_to:
		var a := projection.geo_to_map(Vector2(lon, _geo_bounds.position.y))
		var b := projection.geo_to_map(Vector2(lon, _geo_bounds.end.y))
		_overlay.draw_line(a, b, GRID, 1.0 * s)
		var shown := posmod(lon + 180, 360) - 180
		_draw_text("%d°%s" % [absi(shown), "E" if shown > 0 else ("W" if shown < 0 else "")], b + Vector2(6, 18) * s, 15 * s, GRID_TEXT, false)
		lon += step
	var lat := ceili(_geo_bounds.position.y / step) * step
	var x0 := view.position.x - step if _has_world else _geo_bounds.position.x
	var x1 := view.end.x + step if _has_world else _geo_bounds.end.x
	while lat <= _geo_bounds.end.y:
		var a := projection.geo_to_map(Vector2(x0, lat))
		var b := projection.geo_to_map(Vector2(x1, lat))
		_overlay.draw_line(a, b, GRID, 1.0 * s)
		var label_at := projection.geo_to_map(Vector2(maxf(x0 + step, view.position.x), lat)) if _has_world else a
		_draw_text("%d°%s" % [absi(lat), "N" if lat > 0 else ("S" if lat < 0 else "")], label_at + Vector2(6, -6) * s, 15 * s, GRID_TEXT, false)
		lat += step


func _draw_weather(s: float) -> void:
	# Only the shapes in view (Iteration 16: the weather is worldwide), on the
	# world chart in the copy of the world nearest the view.
	var view := Rect2(screen_to_map(Vector2.ZERO), Vector2.ZERO).expand(screen_to_map(get_viewport_rect().size)).grow(80.0 * s)
	# Risk areas first (underneath), then gales, then storm cells and cyclones.
	var order := [WeatherEvent.KIND_THUNDER_RISK, WeatherEvent.KIND_GALE, WeatherEvent.KIND_CYCLONE, WeatherEvent.KIND_THUNDERSTORM]
	for kind in order:
		for shape in _weather_shapes:
			var event: WeatherEvent = shape.event
			if event.kind != kind:
				continue
			var box: Rect2 = shape.get("bounds", Rect2())
			var shift := INF
			for dx in ([0.0, -_world_width, _world_width] if _has_world else [0.0]):
				if Rect2(box.position + Vector2(dx, 0.0), box.size).intersects(view):
					shift = dx
					break
			if shift == INF:
				continue
			_overlay.draw_set_transform(Vector2(shift, 0.0))
			var style := WeatherStyle.style(kind)
			var color: Color = style.color
			var strength: float = clampf(shape.strength, 0.25, 1.0)
			var outline: PackedVector2Array = shape.outline
			if float(style.fill) > 0.0:
				_overlay.draw_colored_polygon(outline, Color(color, float(style.fill) * strength))
			WeatherStyle.draw_outline(_overlay, outline, style.outline, Color(color, 0.9), 2.5 * s)
			if shape.has("core") and shape.core.size() >= 3:
				_overlay.draw_colored_polygon(shape.core, Color(color, float(style.fill) * strength))
				WeatherStyle.draw_outline(_overlay, shape.core, "dotted", Color(color, 0.8), 1.5 * s)
			# Glyph and label, sized for the screen; labels only on larger shapes.
			var extent := _bounds_of(outline).size
			var on_screen := maxf(extent.x, extent.y) / s
			var center: Vector2 = shape.center
			WeatherStyle.draw_glyph(_overlay, kind, center, clampf(on_screen * 0.25, 14.0, 30.0) * s, Color(color, 1.0))
			if on_screen >= 90.0:
				_draw_text(shape.label, center + Vector2(0, 34) * s, 15 * s, Color(color, 1.0), true, true)
			_overlay.draw_set_transform(Vector2.ZERO)


## The canal links routes may use (data/navigation/canals.json): a thin
## water-coloured line along each, so a course through one follows a visible
## waterway (not on the Dreamer's Map, whose look is its own).
func _draw_canals(s: float) -> void:
	if _dream_tint != null or SeaRouter.get_loaded() == null:
		return
	for canal in SeaRouter.get_loaded().canals:
		for points in _path_copies(canal.points):
			_overlay.draw_polyline(points, Color(SEAFOAM, 0.85), 2.0 * s, true)


func _draw_courses(s: float) -> void:
	if travelled_path.size() >= 2:
		for points in _path_copies(travelled_path):
			_overlay.draw_polyline(points, Color(PORT_FILL, 0.45), 2.0 * s, true)
	if active_path.size() >= 2:
		for points in _path_copies(active_path):
			_overlay.draw_polyline(points, BRASS, 4.0 * s, true)
			_draw_arrowhead(points, BRASS, s)
	for leg in draft_legs:
		for points in _path_copies(leg.path):
			if points.size() < 2:
				continue
			if not leg.ok:
				# Blocked leg: dashed red line with a cross, never only colour.
				for i in range(1, points.size()):
					_overlay.draw_dashed_line(points[i - 1], points[i], INVALID, 3.0 * s, 10.0 * s, true, true)
				var mid := (points[0] + points[points.size() - 1]) / 2.0
				var r := 9.0 * s
				_overlay.draw_line(mid + Vector2(-r, -r), mid + Vector2(r, r), INVALID, 4.0 * s, true)
				_overlay.draw_line(mid + Vector2(-r, r), mid + Vector2(r, -r), INVALID, 4.0 * s, true)
				# A draft only: the course in use is unchanged until Apply.
				_draw_text(Loc.t("BLOCKED (not applied)"), mid + Vector2(14, -10) * s, 15 * s, INVALID, false, true)
				continue
			var color := SEAFOAM if draft_is_proposal else BRASS
			for i in range(1, points.size()):
				_overlay.draw_dashed_line(points[i - 1], points[i], color, 3.5 * s, 12.0 * s, true, true)
	if not draft_legs.is_empty() and draft_legs.back().ok:
		for points in _path_copies(draft_legs.back().path):
			_draw_arrowhead(points, SEAFOAM if draft_is_proposal else BRASS, s)


func _draw_arrowhead(points: PackedVector2Array, color: Color, s: float) -> void:
	if points.size() < 2:
		return
	var end := points[points.size() - 1]
	var direction := (end - points[points.size() - 2]).normalized()
	var tip := end - direction * 14.0 * s
	var side := direction.orthogonal() * 9.0 * s
	_overlay.draw_colored_polygon(PackedVector2Array([tip, tip - direction * 18.0 * s + side,
		tip - direction * 18.0 * s - side]), color)


func _draw_port(port: PortData, s: float, labelled := true) -> void:
	var p := _near_view(projection.geo_to_map(port.get_geo_position()))
	if port.id == selected_port_id:
		_overlay.draw_circle(p, 15.0 * s, BRASS, false, 3.0 * s, true)
	elif port.id == _hovered_port_id:
		_overlay.draw_circle(p, 13.0 * s, HOVER, false, 2.0 * s, true)
	_overlay.draw_circle(p, 8.0 * s, PORT_RIM, true, -1.0, true)
	_overlay.draw_circle(p, 5.5 * s, BRASS if port.id == destination_port_id else PORT_FILL, true, -1.0, true)
	if HarbourLooks.get_default().is_special(port.id):
		_draw_special_star(p + Vector2(-15.0, -10.0) * s, s)
	if labelled:
		# The label rectangle is in screen space (see _update_port_layout()).
		var rect: Rect2 = _labelled_ports[port.id].grow(-PORT_LABEL_GAP_PX / 2.0)
		var baseline := screen_to_map(rect.position + Vector2(0.0, rect.size.y * 0.78))
		_draw_text(port.display_name, baseline, PORT_LABEL_PX * s, PORT_FILL, false, true)


## The special-harbour mark (I021): a small brass compass star on the pin's
## shoulder (upper left, outside the selection ring, clear of the label on
## the right and of a visited pin above), for a harbour with its own
## illustrated arrival.
func _draw_special_star(at: Vector2, s: float) -> void:
	var outer := 7.5 * s
	var inner := 2.6 * s
	var points := PackedVector2Array()
	for i in 8:
		var a := -PI / 2.0 + i * PI / 4.0
		points.append(at + Vector2(cos(a), sin(a)) * (outer if i % 2 == 0 else inner))
	var rim := points.duplicate()
	rim.append(points[0])
	_overlay.draw_colored_polygon(points, BRASS)
	_overlay.draw_polyline(rim, PORT_RIM, 1.4 * s, true)


func _draw_waypoints(s: float) -> void:
	for i in waypoints.size():
		var p := _near_view(projection.geo_to_map(waypoints[i]))
		var r := 9.0 * s
		if i < anchorages.size() and anchorages[i]:
			_draw_anchorage(p, s, i == selected_waypoint, i in invalid_waypoints, i + 1, i < anchorage_magic.size() and anchorage_magic[i])
			continue
		var diamond := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
		if i == selected_waypoint:
			_overlay.draw_circle(p, 15.0 * s, BRASS, false, 3.0 * s, true)
		var closed := diamond.duplicate()
		closed.append(diamond[0])
		_overlay.draw_colored_polygon(diamond, SEAFOAM)
		_overlay.draw_polyline(closed, PORT_RIM, 2.5 * s, true)
		_draw_text(str(i + 1), p + Vector2(12, -8) * s, 16 * s, PORT_FILL, false, true)
		if i in invalid_waypoints:
			_overlay.draw_line(p + Vector2(-r, -r), p + Vector2(r, r), INVALID, 3.5 * s, true)
			_overlay.draw_line(p + Vector2(-r, r), p + Vector2(r, -r), INVALID, 3.5 * s, true)


## An anchorage waypoint: a round navy marker with a brass anchor, numbered
## and labelled (shape and word, never colour alone).
func _draw_anchorage(p: Vector2, s: float, selected: bool, invalid: bool, number: int, magic := false) -> void:
	var r := 12.0 * s
	if selected:
		_overlay.draw_circle(p, r + 6.0 * s, BRASS, false, 3.0 * s, true)
	_overlay.draw_circle(p, r, MAGIC_AMBER if magic else PORT_RIM, true, -1.0, true)
	_overlay.draw_circle(p, r - 2.0 * s, WATER, true, -1.0, true)
	var w := 1.8 * s
	_overlay.draw_circle(p + Vector2(0, -6.5) * s, 2.0 * s, BRASS, false, w, true)  # ring
	_overlay.draw_line(p + Vector2(0, -4.5) * s, p + Vector2(0, 7) * s, BRASS, w, true)  # shank
	_overlay.draw_line(p + Vector2(-4, -2.5) * s, p + Vector2(4, -2.5) * s, BRASS, w, true)  # stock
	_overlay.draw_arc(p + Vector2(0, 1) * s, 6.5 * s, deg_to_rad(20.0), deg_to_rad(160.0), 12, BRASS, w, true)  # arms
	_draw_text(Loc.t("%d  Anchorage%s") % [number, Loc.t("  (Magic Anchor)") if magic else ""], p + Vector2(16, -8) * s, 16 * s, PORT_FILL, false, true)
	if invalid:
		_overlay.draw_line(p + Vector2(-r, -r), p + Vector2(r, r), INVALID, 3.5 * s, true)
		_overlay.draw_line(p + Vector2(-r, r), p + Vector2(r, -r), INVALID, 3.5 * s, true)


func _draw_boat(at: Vector2, s: float, with_leader: bool) -> void:
	# Small sloop glyph echoing the logo, centred on the vessel's position
	# (offset with a leader line when it lies in a port).
	if with_leader:
		_overlay.draw_line(at + Vector2(10, 10) * s, at + Vector2(20, 20) * s, PORT_FILL, 2.0 * s, true)
	var main := PackedVector2Array([at + Vector2(-1, -22) * s, at + Vector2(-1, 2) * s, at + Vector2(-13, 2) * s])
	var jib := PackedVector2Array([at + Vector2(2, -17) * s, at + Vector2(11, 2) * s, at + Vector2(2, 2) * s])
	var hull := PackedVector2Array([at + Vector2(-16, 5) * s, at + Vector2(14, 5) * s,
		at + Vector2(9, 11) * s, at + Vector2(-11, 11) * s])
	if not with_leader:
		_overlay.draw_circle(at, 4.0 * s, BRASS, true, -1.0, true)
	for shape in [main, jib, hull]:
		var outline: PackedVector2Array = shape.duplicate()
		outline.append(shape[0])
		_overlay.draw_polyline(outline, PORT_RIM, 3.0 * s, true)
		_overlay.draw_colored_polygon(shape, BRASS if shape == hull else PORT_FILL)


func _to_map(path: PackedVector2Array) -> PackedVector2Array:
	return projection.geo_polygon_to_map(path)


func _draw_text(text: String, at: Vector2, size: float, color: Color, centered: bool, outlined := false) -> void:
	# Fonts are drawn at a fixed screen size: scale the canvas instead of the
	# font so text stays sharp at every zoom level.
	var font_size := 22
	var factor := size / font_size
	_overlay.draw_set_transform(at, 0.0, Vector2(factor, factor))
	var offset := Vector2.ZERO
	if centered:
		offset.x = -LABEL_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x / 2.0
	if outlined:
		_overlay.draw_string_outline(LABEL_FONT, offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, PORT_RIM)
	_overlay.draw_string(LABEL_FONT, offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	_overlay.draw_set_transform(Vector2.ZERO)
