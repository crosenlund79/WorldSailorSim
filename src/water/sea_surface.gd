class_name SeaSurface
extends Node
## Drives the illustrated sea (sea_surface.gdshader) on a deck's Water
## polygon (Operation Real Horizon). Presentation only: it reads the wind and
## weather at the boat (one sample every SAMPLE_SECONDS, the same values the
## sails and WaterLife use), whether the boat is moored, at anchor or under
## way, and the daylight, and eases the sea towards them so a change of
## weather rolls in rather than snaps.
##
##   calm, sheltered harbour  -> coastal blue-green, glassy, soft reflections
##   open sea, fresh breeze   -> steel blue, swell and chop with the wind
##   gale / thunderstorm      -> slate, short steep seas, whitecaps, streaks
##
## Colours come from MarinePalette. The Water polygon keeps its node and
## colour (tests and the Classic art read them); only its material is set,
## and it is made large enough to fill a zoomed-out or turned view.

const SHADER := preload("res://src/water/sea_surface.gdshader")
const SAMPLE_SECONDS := 0.5
## How fast the sea follows a change (per second).
const EASE := 0.6
## Scene units per second per knot the pattern streams aft (as WaterLife).
const FLOW_PX_PER_KN := 9.0
const EXTENT := 5200.0

var area: BoatArea
var water: Polygon2D
var material: ShaderMaterial
## Targets and current values (tests read these).
var sea_state := 0.3
var shelter := 1.0
var storm := 0.0
var rain := 0.0
var sun := 1.0
var _target := {"sea_state": 0.3, "shelter": 1.0, "storm": 0.0, "rain": 0.0, "sun": 1.0}
var _wind_dir := Vector2.RIGHT
var _boat_kn := 0.0
var _flow := Vector2.ZERO
var _time := 0.0
var _sample_in := 0.0


func setup(boat_area: BoatArea, water_polygon: Polygon2D) -> void:
	area = boat_area
	water = water_polygon
	name = "SeaSurface"
	material = ShaderMaterial.new()
	material.shader = SHADER
	water.material = material
	water.polygon = PackedVector2Array([Vector2(-EXTENT, -EXTENT), Vector2(EXTENT, -EXTENT), Vector2(EXTENT, EXTENT),
		Vector2(-EXTENT, EXTENT)])
	_sample()
	for key: String in _target:
		set(key, _target[key])
	_apply()


## Sea state 0..1 for a wind speed (knots): glassy below 3, a gale near 1.
static func sea_state_for(wind_kn: float) -> float:
	return clampf((wind_kn - 2.0) / 34.0, 0.0, 1.0)


## How stormy the sky and sea look (0..1) for a weather sample.
static func storm_for(sample: WeatherSample) -> float:
	if sample == null:
		return 0.0
	if sample.thunder_active or sample.classification in [WeatherModel.CLASS_THUNDERSTORM, WeatherModel.CLASS_SQUALL,
			WeatherModel.CLASS_TROPICAL_STORM, WeatherModel.CLASS_HURRICANE]:
		return 1.0
	match sample.classification:
		WeatherModel.CLASS_STORM:
			return 0.9
		WeatherModel.CLASS_GALE:
			return 0.7
		WeatherModel.CLASS_STRONG_WIND:
			return 0.35
	return 0.25 if sample.thunder_possible else 0.0


func _sample() -> void:
	if not GameSession.is_active():
		return
	var here := Simulation.get_weather_at_vessel()
	var underway := GameSession.is_underway()
	var heading := area.get_view_heading() if underway and area else 0.0
	_wind_dir = Vector2.from_angle(deg_to_rad(here.from_deg + 180.0 - heading))
	_boat_kn = GameSession.get_vessel_speed_kn() if underway else 0.0
	var anchored := GameSession.is_anchored()
	_target.shelter = 0.0 if underway else (0.55 if anchored else 1.0)
	# In harbour the breakwater takes most of the sea out of the wind.
	_target.sea_state = sea_state_for(here.speed_kn) * (1.0 - _target.shelter * 0.6)
	_target.storm = storm_for(here)
	_target.rain = WeatherAudio.rain_level(here)
	var elevation := Daylight.sun_elevation(GameSession.get_vessel_position(), GameSession.get_game_time())
	_target.sun = smoothstep(2.0, 20.0, elevation) * (1.0 - _target.storm)


func _process(delta: float) -> void:
	if water == null or not is_instance_valid(water):
		return
	_time += delta
	_sample_in -= delta
	if _sample_in <= 0.0:
		_sample_in = SAMPLE_SECONDS
		_sample()
	var k := 1.0 - exp(-EASE * delta)
	for key: String in _target:
		set(key, lerpf(get(key), _target[key], k))
	_flow += Vector2.LEFT * _boat_kn * FLOW_PX_PER_KN * delta
	_apply()


func _apply() -> void:
	var base := MarinePalette.sea_colour(shelter, storm)
	var deep := MarinePalette.DEEP_SEA.lerp(MarinePalette.HARBOUR_WATER, shelter * 0.6).lerp(MarinePalette.STORM_SEA.darkened(0.2), storm * 0.7)
	material.set_shader_parameter(&"base_colour", base)
	material.set_shader_parameter(&"deep_colour", deep)
	material.set_shader_parameter(&"light_colour", MarinePalette.WAVE_LIGHT.lerp(MarinePalette.STORM_SKY, storm * 0.5))
	material.set_shader_parameter(&"shadow_colour", MarinePalette.WAVE_SHADOW.lerp(Color("#151F24"), storm * 0.6))
	material.set_shader_parameter(&"foam_colour", MarinePalette.FOAM)
	material.set_shader_parameter(&"wind_dir", _wind_dir)
	material.set_shader_parameter(&"sea_state", sea_state)
	material.set_shader_parameter(&"shelter", shelter)
	material.set_shader_parameter(&"sun", sun)
	material.set_shader_parameter(&"rain", rain)
	material.set_shader_parameter(&"flow", _flow)
	material.set_shader_parameter(&"sea_time", _time)
