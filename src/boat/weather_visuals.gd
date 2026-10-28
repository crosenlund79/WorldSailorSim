class_name WeatherVisuals
extends Node2D
## The weather seen on deck (Iteration 17): light wind streaks drifting with
## the wind, and rain when it rains (WeatherAudio.rain_level: the same rule
## the rain sound follows). Both read the wind and weather at the boat only
## (one sample every SAMPLE_SECONDS), never a field, and agree with it: the
## streaks travel where the wind blows to, faster and more of them in more
## wind; the rain slants with it.
##
## Boat coordinates: the bow is +x, starboard +y. A wind blowing to compass
## direction W, on heading H, blows towards (W - H) clockwise from the bow.
## In harbour the boat lies bow east, as drawn.

const SAMPLE_SECONDS := 0.5
const MAX_STREAKS := 40
const MAX_DROPS := 260
const STREAK := Color(0.88, 0.92, 0.93)
const DROP := Color(0.80, 0.85, 0.88)

var area: BoatArea
## Where the wind blows to, as a unit vector in boat coordinates, and its
## strength; rain 0..1 (tests read these).
var wind_direction := Vector2.RIGHT
var wind_kn := 0.0
var rain := 0.0
var _sample_in := 0.0
var _streaks: Array[Vector3] = []  # x, y, age 0..1
var _drops: Array[Vector3] = []  # x, y, length
var _rng := RandomNumberGenerator.new()
var _bounds := Rect2()


func setup(boat_area: BoatArea) -> void:
	area = boat_area
	name = "WeatherVisuals"
	z_index = 40
	_rng.seed = 7
	_bounds = area.walkable_bounds.grow(650.0)


static func boat_relative(to_deg: float, heading_deg: float) -> Vector2:
	var rel := deg_to_rad(to_deg - heading_deg)
	return Vector2(cos(rel), sin(rel))


func _process(delta: float) -> void:
	if area == null or not GameSession.is_active():
		return
	_sample_in -= delta
	if _sample_in <= 0.0:
		_sample_in = SAMPLE_SECONDS
		var here := Simulation.get_weather_at_vessel()
		var heading := Simulation.get_current_heading() if GameSession.is_underway() else 90.0
		wind_direction = boat_relative(here.from_deg + 180.0, heading)
		wind_kn = here.speed_kn
		rain = WeatherAudio.rain_level(here)
	_update_streaks(delta)
	_update_drops(delta)
	queue_redraw()


func _update_streaks(delta: float) -> void:
	var wanted := 0 if wind_kn < 3.0 else int(clampf(wind_kn / 30.0, 0.15, 1.0) * MAX_STREAKS)
	var speed := 50.0 + wind_kn * 9.0
	for i in range(_streaks.size() - 1, -1, -1):
		var s := _streaks[i]
		s.x += wind_direction.x * speed * delta
		s.y += wind_direction.y * speed * delta
		s.z += delta / 2.2
		if s.z >= 1.0 or i >= wanted:
			_streaks.remove_at(i)
		else:
			_streaks[i] = s
	while _streaks.size() < wanted:
		var p := Vector2(_rng.randf_range(_bounds.position.x, _bounds.end.x), _rng.randf_range(_bounds.position.y, _bounds.end.y))
		_streaks.append(Vector3(p.x, p.y, _rng.randf_range(0.0, 0.6)))


func _update_drops(delta: float) -> void:
	var wanted := int(rain * MAX_DROPS)
	var fall := Vector2(wind_direction.x, wind_direction.y) * clampf(wind_kn * 6.0, 0.0, 220.0) + Vector2(0, 380.0)
	for i in range(_drops.size() - 1, -1, -1):
		var d := _drops[i]
		d.x += fall.x * delta * 0.4
		d.y += fall.y * delta
		if d.y > _bounds.end.y or i >= wanted:
			_drops.remove_at(i)
		else:
			_drops[i] = d
	while _drops.size() < wanted:
		_drops.append(Vector3(_rng.randf_range(_bounds.position.x, _bounds.end.x), _rng.randf_range(_bounds.position.y, _bounds.end.y),
			_rng.randf_range(10.0, 22.0)))


func get_streak_count() -> int:
	return _streaks.size()


func get_drop_count() -> int:
	return _drops.size()


func _draw() -> void:
	var strength := clampf(wind_kn / 25.0, 0.2, 1.0)
	for s in _streaks:
		var at := Vector2(s.x, s.y)
		var fade := sin(PI * s.z)
		var length := 26.0 + wind_kn * 1.6
		draw_line(at - wind_direction * length * 0.5, at + wind_direction * length * 0.5,
			Color(STREAK, 0.08 * fade * strength), 1.2, true)
	var slant := (Vector2(wind_direction.x * clampf(wind_kn * 6.0, 0.0, 220.0) * 0.4, 380.0)).normalized()
	for d in _drops:
		var at := Vector2(d.x, d.y)
		draw_line(at, at + slant * d.z, Color(DROP, 0.28), 1.0, true)
