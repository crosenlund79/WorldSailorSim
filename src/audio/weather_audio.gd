class_name WeatherAudio
extends Node
## The sound of the weather aboard (Iteration 17), from the one weather
## model at the boat (Simulation.get_weather_at_vessel), checked once a real
## second by the App:
## - wind: a soft breeze loop that rises gently with the wind (with a slow
##   swell of its own, so it never drones), and above STORM_AUDIBLE_KN the
##   strong-wind loop as before;
## - water along the hull: louder underway and in a breeze, quiet in harbour;
## - rain: the weather model has no rain of its own, so rain follows the
##   systems that bring it (heavy in thunderstorms, squalls and tropical
##   storms, steady in gales, showers in thunderstorm-risk areas) - see
##   rain_level();
## - lightning and thunder in a thunderstorm at or near the boat: a short,
##   gentle flash pattern through the boat's lighting (BoatLighting.flash,
##   scaled by the Flash brightness setting; one soft flash with Reduce
##   flashing), then thunder after a delay that grows with the distance to
##   the storm (near: a crack and a roll; far: a low rumble).
## Below deck everything outside is muffled: the weather sounds play on the
## "Outside" bus (sent to Ambience, so the Ambience volume governs them) whose
## low-pass filter closes when the captain goes below and opens on deck. The
## SFX and UI buses are never filtered, so later alarms stay clear anywhere.
## The wind (breeze and storm) plays on the "Wind" bus (I022), which sends to
## Outside: muffled below deck as before, with its own volume in Settings.

const OUTSIDE_BUS := &"Outside"
const WIND_BUS := &"Wind"
const WIND_LOOP := &"wind_breeze"
const WATER_LOOP := &"water_hull"
const RAIN_LOOP := &"rain"
const STORM_LOOP := &"storm_wind"
const STORM_AUDIBLE_KN := 20.0
const STORM_FULL_KN := 45.0
const FADE := 3.0
## Low-pass cutoff (Hz) and bus level (dB) on deck and below.
const OPEN_HZ := 20000.0
const MUFFLED_HZ := 650.0
const MUFFLED_DB := -5.0
## Lightning: storms farther than this (nm) are not seen or heard.
const STORM_RANGE_NM := 25.0

var breeze_sound: AudioStream = preload("res://assets/audio/weather/wind_breeze.wav")
var water_sound: AudioStream = preload("res://assets/audio/weather/water_hull.wav")
var rain_sound: AudioStream = preload("res://assets/audio/weather/rain.wav")
var thunder_near_sound: AudioStream = preload("res://assets/audio/weather/thunder_near.wav")
var thunder_far_sound: AudioStream = preload("res://assets/audio/weather/thunder_far.wav")
var storm_wind_sound: AudioStream = preload("res://assets/audio/placeholder/storm_wind.wav")

## Where the captain is: "deck", "inside" (cabin or chart table) or "" (no
## boat: nothing plays).
var place := ""
var _muffle := 0.0
var _muffle_target := 0.0
var _rng := RandomNumberGenerator.new()  # cosmetic only (timing of strikes)
var _strike_in := 0.0
var _thunder_in := 0.0
var _thunder_near := false
var _thunder_db := -8.0
var _storm_nm := INF
## Flashes still to come in this strike: [[delay s, strength]].
var _flashes: Array = []
var lighting_provider := Callable()
## The last levels set (tests and diagnostics).
var levels := {"wind": 0.0, "water": 0.0, "rain": 0.0, "storm": 0.0}
var strikes := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.randomize()


## How hard it rains for a weather sample, 0..1 (see the class notes).
static func rain_level(sample: WeatherSample) -> float:
	if sample == null:
		return 0.0
	if sample.thunder_active or sample.classification in [WeatherModel.CLASS_THUNDERSTORM, WeatherModel.CLASS_SQUALL,
			WeatherModel.CLASS_TROPICAL_STORM, WeatherModel.CLASS_HURRICANE]:
		return 1.0
	if sample.classification in [WeatherModel.CLASS_GALE, WeatherModel.CLASS_STORM]:
		return 0.6
	if sample.thunder_possible:
		return 0.25
	return 0.0


static func outside_bus_index() -> int:
	return AudioServer.get_bus_index(OUTSIDE_BUS)


## Once a real second: the loops for the weather at the boat, and whether a
## storm is near enough for lightning.
func update(here: WeatherSample, new_place: String, underway: bool, storms: Array) -> void:
	place = new_place
	if place.is_empty() or here == null:
		for id in [WIND_LOOP, WATER_LOOP, RAIN_LOOP, STORM_LOOP]:
			AudioManager.stop_loop(id, FADE * 0.5)
		levels = {"wind": 0.0, "water": 0.0, "rain": 0.0, "storm": 0.0}
		_strike_in = 0.0
		_storm_nm = INF
		return
	_muffle_target = 0.0 if place == "deck" else 1.0
	var wind := clampf(here.speed_kn / 25.0, 0.0, 1.0)
	levels.wind = wind
	_loop(WIND_LOOP, breeze_sound, wind, -34.0, -14.0, WIND_BUS)
	var water := clampf((0.35 + GameSession.get_vessel_speed_kn() / 10.0 * 0.4 + wind * 0.25) if underway else 0.15 + wind * 0.2, 0.0, 1.0)
	levels.water = water
	_loop(WATER_LOOP, water_sound, water, -30.0, -12.0)
	var rain := rain_level(here)
	levels.rain = rain
	_loop(RAIN_LOOP, rain_sound, rain, -26.0, -8.0)
	var storm := clampf(inverse_lerp(STORM_AUDIBLE_KN, STORM_FULL_KN, here.speed_kn), 0.0, 1.0) if here.speed_kn > STORM_AUDIBLE_KN else 0.0
	levels.storm = storm
	_loop(STORM_LOOP, storm_wind_sound, storm, -30.0, -6.0, WIND_BUS)
	# The nearest thunderstorm cell (at the boat: right here).
	_storm_nm = INF
	if here.thunder_active:
		_storm_nm = _rng.randf_range(0.5, 2.5)
	for event: WeatherEvent in storms:
		var d := maxf(event.offset_nm(GameSession.get_vessel_position(), GameSession.get_game_time()).length() - event.radius_nm * 0.5, 0.3)
		_storm_nm = minf(_storm_nm, d)
	if _storm_nm <= STORM_RANGE_NM and _strike_in <= 0.0:
		_strike_in = _rng.randf_range(6.0, 18.0) * (0.6 if _storm_nm < 3.0 else 1.0)
	elif _storm_nm > STORM_RANGE_NM:
		_strike_in = 0.0


func _loop(id: StringName, stream: AudioStream, level: float, quiet_db: float, loud_db: float, bus := OUTSIDE_BUS) -> void:
	if level <= 0.01:
		AudioManager.stop_loop(id, FADE)
	else:
		AudioManager.play_loop(id, stream, lerpf(quiet_db, loud_db, level), FADE, bus)


func _process(delta: float) -> void:
	_update_muffle(delta)
	if _strike_in > 0.0:
		_strike_in -= delta
		if _strike_in <= 0.0:
			strike(_storm_nm)
	if not _flashes.is_empty():
		_flashes[0][0] -= delta
		if _flashes[0][0] <= 0.0:
			var lighting := _lighting()
			if lighting:
				lighting.flash(float(_flashes[0][1]))
			_flashes.pop_front()
	if _thunder_in > 0.0:
		_thunder_in -= delta
		if _thunder_in <= 0.0:
			AudioManager.play_one_shot(thunder_near_sound if _thunder_near else thunder_far_sound, OUTSIDE_BUS, _thunder_db)


## A lightning strike `distance_nm` away: the flash now, the thunder later.
func strike(distance_nm: float) -> void:
	if place.is_empty() or is_inf(distance_nm):
		return
	strikes += 1
	var strength := clampf(1.15 - distance_nm / 10.0, 0.15, 1.0)
	_flashes.clear()
	if SettingsManager.get_reduce_flashing():
		_flashes.append([0.0, strength * 0.45])
	else:
		_flashes.append_array([[0.0, strength], [0.09, strength * 0.55], [0.16, strength * 0.8]])
	_thunder_near = distance_nm < 3.0
	_thunder_db = lerpf(-2.0, -14.0, clampf(distance_nm / STORM_RANGE_NM, 0.0, 1.0))
	_thunder_in = clampf(0.25 + distance_nm * 1.4, 0.25, 9.0)  # a lighthearted speed of sound


func get_thunder_delay() -> float:
	return _thunder_in


func get_muffle() -> float:
	return _muffle


func _update_muffle(delta: float) -> void:
	_muffle = move_toward(_muffle, _muffle_target, delta / 0.6)
	var index := outside_bus_index()
	if index < 0:
		return
	var filter := AudioServer.get_bus_effect(index, 0) as AudioEffectLowPassFilter
	if filter:
		filter.cutoff_hz = exp(lerpf(log(OPEN_HZ), log(MUFFLED_HZ), _muffle))
	AudioServer.set_bus_volume_db(index, lerpf(0.0, MUFFLED_DB, _muffle))


func _lighting() -> BoatLighting:
	return lighting_provider.call() if lighting_provider.is_valid() else null
