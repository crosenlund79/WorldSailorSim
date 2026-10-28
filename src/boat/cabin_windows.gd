class_name CabinWindows
extends Node2D
## The cabin windows (I022; all four cabins since I025): plain glass.
##
## The cabin is seen from above, so a window is a short opening in the wall
## band of the illustrated cabin (data/vessels/cabin_windows.json): portlights
## in the monohulls' and the catamaran's hull sides, and the catamaran's big
## saloon windows looking forward. The cabin painters
## (tools/vessels/cabin_joinery.py) paint each opening's recess from the
## same file, so the glass always sits in its frame.
##
## I025 (the Captain's revision): the windows no longer show a live view of
## the world outside. Each is smoked acrylic in an anodised frame: a little
## daylight through the outer edge of the glass, deeper towards the cabin, a
## soft reflection across it; at night dark glass with a faint warm glint of
## the cabin lamps. The cabin's own lighting (BoatLighting) dims it with the
## rest of the cabin; the glass itself only follows daylight, read once every
## REFRESH_SECONDS (one sun-elevation sum, no weather, no harbour, no sea).
## The faded sea round the hull is a separate thing (CabinSeaBackdrop).
##
## Everything is drawn inside the opening's own rectangle, then the frame
## over its edge; the node sits right above the cabin's wall art (whose
## recess the frame covers) and under the furniture.
##
## Cost: a few rectangles per window, drawn when the cabin opens and again
## only when the daylight has changed noticeably.

const DATA_PATH := "res://data/vessels/cabin_windows.json"
const FRAME := Color(0.52, 0.57, 0.59)  # anodised frame (Real Horizon)
const FRAME_SHADOW := Color(0.06, 0.08, 0.09, 0.85)
## Glass by day (outer edge, inner edge) and by night.
const DAY_OUTER := Color(0.66, 0.74, 0.77)
const DAY_INNER := Color(0.36, 0.45, 0.5)
const NIGHT_OUTER := Color(0.13, 0.16, 0.21)
const NIGHT_INNER := Color(0.07, 0.09, 0.12)
const REFLECTION := Color(1.0, 1.0, 1.0, 0.16)
const LAMP_GLINT := Color(1.0, 0.82, 0.55, 0.22)
## How often the daylight is read, and how much it must change to redraw.
const REFRESH_SECONDS := 20.0
const DAYLIGHT_STEP := 0.04
## Which way each side looks out (before the wall's slope).
const SIDES := {"port": Vector2.UP, "starboard": Vector2.DOWN, "forward": Vector2.RIGHT, "aft": Vector2.LEFT}

var area: BoatArea
## [{"at": Vector2, "length", "thickness", "angle", "side"}]
var windows: Array[Dictionary] = []
## Daylight as last read (0 night .. 1 day).
var daylight := 1.0

## Microseconds the last _draw took (diagnostics and the performance test).
var last_draw_usec := 0

var _refresh_left := 0.0
static var _data := {}


## The windows of `vessel_id` from the data file ([] when it has none).
static func windows_for(vessel_id: StringName) -> Array[Dictionary]:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_data = parsed if parsed is Dictionary else {"windows": {}}
	var out: Array[Dictionary] = []
	for entry: Variant in (_data.get("windows", {}) as Dictionary).get(String(vessel_id), []):
		if entry is Dictionary and entry.get("at") is Array and (entry.at as Array).size() == 2:
			out.append({"at": Vector2(float(entry.at[0]), float(entry.at[1])), "length": float(entry.get("length", 50)),
				"thickness": float(entry.get("thickness", 14)), "angle": float(entry.get("angle", 0)),
				"side": String(entry.get("side", "port")) if SIDES.has(String(entry.get("side", "port"))) else "port"})
	return out


## A window's axes: {"outward": out of the boat through the opening,
## "right": along the opening, to the right of someone looking out}.
static func axes(window: Dictionary) -> Dictionary:
	var outward: Vector2 = (SIDES.get(String(window.side), Vector2.UP) as Vector2).rotated(deg_to_rad(float(window.angle)))
	return {"outward": outward, "right": outward.rotated(PI * 0.5)}


## The glass at `light` (0 night .. 1 day): [outer edge, inner edge].
static func glass_colours(light: float) -> Array[Color]:
	var t := clampf(light, 0.0, 1.0)
	return [NIGHT_OUTER.lerp(DAY_OUTER, t), NIGHT_INNER.lerp(DAY_INNER, t)]


## Returns false (and does nothing) when the boat has no windows.
func setup(boat_area: BoatArea, vessel_id: StringName) -> bool:
	area = boat_area
	windows = windows_for(vessel_id)
	if windows.is_empty():
		return false
	daylight = _read_daylight()
	_refresh_left = REFRESH_SECONDS
	return true


func _process(delta: float) -> void:
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = REFRESH_SECONDS
	if not GameSession.is_active():
		return
	var light := _read_daylight()
	if absf(light - daylight) >= DAYLIGHT_STEP:
		daylight = light
		queue_redraw()


func _read_daylight() -> float:
	if not GameSession.is_active():
		return 1.0
	return Daylight.daylight(Daylight.sun_elevation(GameSession.get_vessel_position(), GameSession.get_game_time()))


func _draw() -> void:
	var start := Time.get_ticks_usec()
	var colours := glass_colours(daylight)
	for window in windows:
		var frame := axes(window)
		draw_set_transform_matrix(Transform2D(frame.right, -frame.outward, window.at))
		_draw_window(window, colours)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	last_draw_usec = Time.get_ticks_usec() - start


func _draw_window(window: Dictionary, colours: Array[Color]) -> void:
	var half_len := float(window.length) * 0.5
	var half_th := float(window.thickness) * 0.5
	var box := Rect2(-half_len, -half_th, half_len * 2.0, half_th * 2.0)
	# The glass: lighter at the outer edge (the light comes from outside).
	_quad(box, colours[0], colours[1])
	# A soft reflection slanting across it, by day; a warm lamp glint by night.
	var slant := minf(half_th * 1.4, half_len * 0.4)
	var x0 := -half_len * 0.35
	var streak := PackedVector2Array([Vector2(x0, -half_th), Vector2(x0 + half_len * 0.18, -half_th),
		Vector2(x0 + half_len * 0.18 - slant, half_th), Vector2(x0 - slant, half_th)])
	var shine := _clip(streak, box)
	if shine.size() >= 3:
		draw_colored_polygon(shine, Color(REFLECTION, REFLECTION.a * lerpf(0.35, 1.0, daylight)))
	if daylight < 0.4:
		draw_circle(Vector2(half_len * 0.45, half_th * 0.35), minf(half_th * 0.35, 2.4), Color(LAMP_GLINT, LAMP_GLINT.a * (1.0 - daylight / 0.4)))
	# The frame in front of everything.
	draw_rect(box.grow(1.2), FRAME, false, 2.4)
	draw_line(Vector2(-half_len, half_th + 1.6), Vector2(half_len, half_th + 1.6), FRAME_SHADOW, 1.2)


## `polygon` cut to `box` (the streak never leaves the glass).
static func _clip(polygon: PackedVector2Array, box: Rect2) -> PackedVector2Array:
	var rect := PackedVector2Array([box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)])
	var cut := Geometry2D.intersect_polygons(polygon, rect)
	return cut[0] if not cut.is_empty() else PackedVector2Array()


## A gradient from `top` (the outer edge) to `bottom` (the inner edge).
func _quad(rect: Rect2, top: Color, bottom: Color) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	draw_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]),
		PackedColorArray([top, top, bottom, bottom]))
