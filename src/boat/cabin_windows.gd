class_name CabinWindows
extends Node2D
## The world beyond the cabin windows (I022), proof of concept on one cabin.
##
## The cabin is seen from above, so a window is a short opening in the wall
## band of the illustrated cabin (data/vessels/cabin_windows.json). Each
## opening shows a slice of one shared, cheap 360° panorama around the boat,
## flattened into the opening with "up" pointing out of the boat: sky at the
## outer edge, the horizon, the sea nearer the cabin.
##
## The slice is view-dependent: its compass bearing is the boat's heading,
## plus the window's side and the slope of the wall, plus the angle from the
## captain through the window; its width is the angle the opening covers seen
## from where the captain stands (narrow from afar, wide up close). So port and
## starboard show different things, and walking past a window turns the view.
##
## What the panorama holds, all from the game's own state:
##   sky   - the colours of the sun's elevation (day, dusk, night) and the
##           weather (grey when overcast); the sun at its real bearing; stars
##           at night
##   sea   - WaterLook's water colour, lit by the hour; wave crests that grow
##           and whiten with the wind and the weather's hazard
##   shore - moored, the harbour's own landmark art (HarbourLooks, I021) on
##           the quay side (starboard, as the boat lies), its far shore small
##           across the water to port; lit windows in it at night
##   rain  - streaks on the glass when it rains
##   glass - a faint tint over everything (GLASS_TINT, glass_strength), kept
##           apart from the water's own translucency (WaterLook)
## The cabin's frames are drawn over the scenery, so it never shows outside
## the openings; the node sits right above the cabin's wall art and under
## the furniture.
##
## Cost: a few dozen draw calls, redrawn only when the captain moves or every
## REFRESH_SECONDS for the time and weather; no shader, no viewport, no
## second world.

const DATA_PATH := "res://data/vessels/cabin_windows.json"
const GLASS_TINT := Color(0.62, 0.7, 0.72)  # smoked acrylic
const FRAME := Color(0.52, 0.57, 0.59)  # anodised frame (Real Horizon)
const FRAME_SHADOW := Color(0.06, 0.08, 0.09, 0.85)
## Where the horizon lies, from the outer edge (0) to the inner edge (1).
const HORIZON := 0.55
const FOV_MIN := 16.0
const FOV_MAX := 80.0
const REFRESH_SECONDS := 2.0
const MOVE_EPSILON := 1.5
## The harbour's landmark art spans this many degrees on the quay side.
const QUAY_HALF := 40.0
const FAR_SHORE_HALF := 22.0

## The glass tint's strength (0: clear glass). Independent of WaterLook.
static var glass_strength := 0.2

var area: BoatArea
## [{"at": Vector2, "length", "thickness", "angle", "side"}]
var windows: Array[Dictionary] = []
## The world as last sampled (see _sample_world).
var world := {}

## Microseconds the last _draw took (diagnostics and the performance test).
var last_draw_usec := 0

var _viewer := Vector2.INF
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
				"side": String(entry.get("side", "port"))})
	return out


## Returns false (and does nothing) when the boat has no windows.
func setup(boat_area: BoatArea, vessel_id: StringName) -> bool:
	area = boat_area
	windows = windows_for(vessel_id)
	if windows.is_empty():
		return false
	_sample_world()
	return true


func _process(delta: float) -> void:
	if area == null or not GameSession.is_active():
		return
	_refresh_left -= delta
	var viewer := viewer_position()
	if _refresh_left <= 0.0:
		_refresh_left = REFRESH_SECONDS
		_sample_world()
		_viewer = viewer
		queue_redraw()
	elif viewer.distance_to(_viewer) > MOVE_EPSILON:
		_viewer = viewer
		queue_redraw()


## Where the captain stands, in this node's (the cabin's) coordinates.
func viewer_position() -> Vector2:
	return to_local(area.player.global_position) if area and is_instance_valid(area.player) else Vector2.ZERO


## Reads the time, light, weather and place once (on refresh only).
func _sample_world() -> void:
	var geo := GameSession.get_vessel_position()
	var now := GameSession.get_game_time()
	var underway := GameSession.is_underway()
	var sample := Simulation.get_weather_at_vessel()
	var overcast := BoatLighting.overcast_of(sample)
	var elevation := Daylight.sun_elevation(geo, now)
	world = {
		"heading": Simulation.get_current_heading() if underway else 90.0,
		"elevation": elevation,
		"sun_bearing": fposmod(180.0 + (Daylight.local_solar_hours(geo.x, now) - 12.0) * 15.0, 360.0),
		"daylight": Daylight.daylight(elevation),
		"overcast": overcast,
		"rain": WeatherAudio.rain_level(sample),
		"wind_kn": sample.speed_kn,
		"hazard": sample.hazard,
		"moored": not underway,
		"picture": HarbourLooks.get_default().picture_for(GameSession.get_location_id()) if not underway else null,
		"water": MarinePalette.sea_colour(1.0 if WaterLook.is_shallow() else 0.0, overcast),
		"time": now,
	}


## How window `window` is seen from `viewer`: {"centre": compass bearing at
## its middle, "fov": degrees it covers, "right", "outward": unit vectors}.
func view_of(window: Dictionary, viewer: Vector2) -> Dictionary:
	var port := String(window.side) == "port"
	var along := Vector2.RIGHT.rotated(deg_to_rad(float(window.angle)))
	var outward := (Vector2.UP if port else Vector2.DOWN).rotated(deg_to_rad(float(window.angle)))
	var right := along if port else -along
	var to_window: Vector2 = window.at - viewer
	var depth := maxf(to_window.dot(outward), 8.0)
	var off := rad_to_deg(atan2(to_window.dot(right), depth))
	var fov := clampf(2.0 * rad_to_deg(atan2(float(window.length) * 0.5, depth)), FOV_MIN, FOV_MAX)
	var side_bearing := rad_to_deg(outward.angle())  # from the bow (+x): port -90, starboard +90
	var centre := fposmod(float(world.get("heading", 90.0)) + side_bearing + off, 360.0)
	return {"centre": centre, "fov": fov, "right": right, "outward": outward}


func _draw() -> void:
	if world.is_empty():
		return
	var start := Time.get_ticks_usec()
	var viewer := viewer_position()
	for window in windows:
		var view := view_of(window, viewer)
		draw_set_transform_matrix(Transform2D(view.right, -view.outward, window.at))
		_draw_window(window, view)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	last_draw_usec = Time.get_ticks_usec() - start


static func _angle_diff(a: float, b: float) -> float:
	return fposmod(a - b + 180.0, 360.0) - 180.0


func _draw_window(window: Dictionary, view: Dictionary) -> void:
	var half_len := float(window.length) * 0.5
	var half_th := float(window.thickness) * 0.5
	var box := Rect2(-half_len, -half_th, half_len * 2.0, half_th * 2.0)
	var horizon := -half_th + float(window.thickness) * HORIZON
	var centre: float = view.centre
	var fov: float = view.fov
	var to_u := func(bearing: float) -> float: return _angle_diff(bearing, centre) / (fov * 0.5) * half_len
	var day: float = world.daylight
	var overcast: float = world.overcast
	# Sky.
	# Real Horizon: a high grey-blue sky over sea haze, a restrained dusk.
	var top := MarinePalette.NIGHT_SKY.lerp(Color(0.56, 0.66, 0.72), day)
	var low := Color(0.16, 0.2, 0.26).lerp(MarinePalette.SEA_HAZE, day)
	var dusk := clampf(1.0 - absf(float(world.elevation) - 1.0) / 9.0, 0.0, 1.0)
	low = low.lerp(Color(0.88, 0.76, 0.68), dusk * 0.5)
	var grey := MarinePalette.OVERCAST_SKY.darkened(0.12) * lerpf(0.35, 1.0, day)
	top = top.lerp(grey, overcast * 0.8)
	low = low.lerp(grey.lightened(0.1), overcast * 0.7)
	_quad(Rect2(box.position, Vector2(box.size.x, horizon - box.position.y)), top, low)
	# Stars at night (fixed bearings, so they stay put as the view turns).
	if day < 0.2 and overcast < 0.5:
		for k in range(int(floor((centre - fov * 0.5) / 6.0)), int(ceil((centre + fov * 0.5) / 6.0)) + 1):
			var h := hash(k * 7919 % 360) % 100
			if h < 45:
				var u: float = to_u.call(float(k) * 6.0 + (h % 5))
				var v := -half_th + 1.5 + float(h % 7) / 7.0 * (horizon + half_th - 3.0)
				if absf(u) < half_len - 1.0:
					draw_rect(Rect2(u - 0.6, v - 0.6, 1.2, 1.2), Color(1, 0.97, 0.85, 0.85 * (1.0 - day * 5.0)))
	# The sun, at its bearing, low or high in the window by its elevation.
	if float(world.elevation) > -3.0 and overcast < 0.7:
		var su: float = to_u.call(float(world.sun_bearing))
		if absf(su) < half_len + 3.0:
			var rise := clampf(float(world.elevation) / 30.0, 0.0, 1.0)
			var r := 2.4
			var sv := clampf(horizon - 2.0 - rise * (horizon + half_th - 4.0), -half_th + r, horizon - 1.0)
			var glow := Color(1.0, 0.94, 0.84, 0.3 * (1.0 - overcast))
			var gx0 := clampf(su - 10.0, -half_len, half_len)
			var gx1 := clampf(su + 10.0, -half_len, half_len)
			_quad(Rect2(gx0, -half_th, gx1 - gx0, horizon + half_th), Color(glow, 0.0), glow)
			if absf(su) < half_len - r:
				draw_circle(Vector2(su, sv), r, Color(1.0, 0.97, 0.9, 1.0 - overcast))
	# The shore, moored: the harbour to starboard (as the boat lies), its far side small to port.
	var picture := world.get("picture") as Texture2D
	if picture and bool(world.moored):
		var heading := float(world.heading)
		_draw_shore(picture, heading + 90.0, QUAY_HALF, 0.85, box, horizon, centre, fov, day)
		_draw_shore(picture, heading - 90.0, FAR_SHORE_HALF, 0.38, box, horizon, centre, fov, day)
	# The sea.
	var light := Daylight.outside_colour(float(world.elevation), overcast).lerp(Color.WHITE, 0.3)
	var water: Color = world.water
	_quad(Rect2(-half_len, horizon, half_len * 2.0, half_th - horizon), water * light, (water * light).darkened(0.15))
	var rough := clampf(float(world.wind_kn) / 25.0 + float(world.hazard) * 0.2, 0.0, 1.0)
	var crest := Color(MarinePalette.FOAM, 0.3 + rough * 0.4) * lerpf(0.45, 1.0, day)
	var drift := float(world.time) / 40.0
	for k in range(int(floor((centre - fov * 0.5) / 4.0)), int(ceil((centre + fov * 0.5) / 4.0)) + 1):
		var h := hash(k * 104729 % 1000)
		if float(h % 100) / 100.0 > 0.35 + rough * 0.5:
			continue
		var u: float = to_u.call(float(k) * 4.0 + fmod(drift + float(h % 13), 4.0))
		var row := float(h % 3 + 1) / 4.0
		var v := horizon + row * (half_th - horizon)
		var w := 1.5 + row * (3.0 + rough * 3.0)
		if absf(u) < half_len - w:
			draw_line(Vector2(u - w, v), Vector2(u + w, v), crest, 0.9 + rough * 0.6)
	# Rain on the glass.
	var rain: float = world.rain
	if rain > 0.05:
		for i in int(4 + rain * 10):
			var x := -half_len + fmod(float(i) * 9.7 + float(world.time) * 0.37, half_len * 2.0)
			var a := Vector2(x, -half_th + 1.0)
			var b := Vector2(clampf(x - 3.0, -half_len, half_len), half_th - 1.0)
			draw_line(a, b, Color(0.85, 0.9, 0.95, 0.3 * rain), 0.8)
	# The glass, then the frame in front of everything.
	draw_rect(box, Color(GLASS_TINT, glass_strength))
	draw_rect(box.grow(1.2), FRAME, false, 2.4)
	draw_line(Vector2(-half_len, half_th + 1.6), Vector2(half_len, half_th + 1.6), FRAME_SHADOW, 1.2)


## The harbour's art on the sky band, spanning `half` degrees around `at`,
## `height` of the sky tall, cut to the window's view.
func _draw_shore(picture: Texture2D, at: float, half: float, height: float, box: Rect2, horizon: float,
		centre: float, fov: float, day: float) -> void:
	var c := _angle_diff(centre, at)
	var lo := maxf(c - fov * 0.5, -half)
	var hi := minf(c + fov * 0.5, half)
	if hi <= lo:
		return
	var half_len := box.size.x * 0.5
	var u0 := (lo - c) / (fov * 0.5) * half_len
	var u1 := (hi - c) / (fov * 0.5) * half_len
	var size := picture.get_size()
	var src := Rect2((lo + half) / (half * 2.0) * size.x, 0.0, (hi - lo) / (half * 2.0) * size.x, size.y)
	var tall := (horizon - box.position.y) * height
	var shade := Color.WHITE * lerpf(0.3, 1.0, day)
	shade.a = 1.0
	draw_texture_rect_region(picture, Rect2(u0, horizon - tall, u1 - u0, tall), src, shade)
	if day < 0.3:
		for k in range(int(lo), int(hi), 3):
			var h := hash(int(at) * 31 + k) % 10
			if h < 4:
				var u := (float(k) - c) / (fov * 0.5) * half_len
				draw_rect(Rect2(u, horizon - tall * (0.2 + float(h) * 0.12), 1.0, 1.0), Color(1.0, 0.82, 0.45, 0.9))


## A vertical gradient (from `top` at the top edge to `bottom`).
func _quad(rect: Rect2, top: Color, bottom: Color) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	draw_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]),
		PackedColorArray([top, top, bottom, bottom]))
