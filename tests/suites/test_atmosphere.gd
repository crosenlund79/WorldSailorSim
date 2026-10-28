extends RefCounted
## Iteration 17 (AUD): the weather aboard.
## - Wind, water and rain loops follow the weather at the boat; the strong
##   wind loop above 20 kn as before; rain follows the systems that bring it.
## - Lightning in a thunderstorm: a short flash pattern through the lighting
##   (scaled by the Flash brightness setting, one soft flash with Reduce
##   flashing), thunder later the farther the storm; near and far thunder.
## - Below deck the outside is muffled (low-pass on the Outside bus); the SFX
##   bus stays unfiltered for later alarms.
## - On deck, wind streaks travel where the wind blows (boat-relative) and
##   rain falls when it rains.
## - The sounds are local, original assets with recorded provenance.

const APP_SCENE := preload("res://src/app/app.tscn")

var t: Node
var app: Node


func run(runner: Node) -> void:
	t = runner
	_test_assets_and_buses()
	_test_rain_rule()
	Simulation.auto_advance = false
	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	app.start_new_game()
	await _settle()
	t.set_wind(270.0, 12.0)
	GameSession.plan_route_to(&"kiel")
	GameSession.depart()
	Simulation.advance(1800.0)
	await _test_loops_and_muffling()
	await _test_lightning()
	await _test_deck_visuals()
	WeatherFixtures.clear()
	SettingsManager.set_reduce_flashing(SettingsManager.DEFAULT_REDUCE_FLASHING)
	SettingsManager.set_flash_intensity(SettingsManager.DEFAULT_FLASH_INTENSITY)
	Simulation.auto_advance = true
	app.queue_free()
	await t.frames(2)
	GameSession.end_session()
	t.use_calm_wind()


func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)


func _show(area: StringName, spawn := &"start") -> BoatArea:
	app.modals.clear()
	GameSession.enter_boat_area(area, spawn)
	app._show_current_boat_area()
	await _settle()
	return app.router.current_screen as BoatArea


func _test_assets_and_buses() -> void:
	var files := ["wind_breeze.wav", "water_hull.wav", "rain.wav", "thunder_near.wav", "thunder_far.wav"]
	var all := true
	for file in files:
		all = all and ResourceLoader.exists("res://assets/audio/weather/" + file)
	var readme := FileAccess.get_file_as_string("res://assets/audio/weather/README.md")
	t.check(all and "generate_weather_audio.py" in readme and "licen" in readme.to_lower(),
		"[assets] the weather sounds are local files with their provenance and licence recorded")
	var outside := AudioServer.get_bus_index(WeatherAudio.OUTSIDE_BUS)
	t.check(outside >= 0 and AudioServer.get_bus_send(outside) == &"Ambience" and AudioServer.get_bus_effect(outside, 0) is AudioEffectLowPassFilter,
		"[buses] an Outside bus with a low-pass filter feeds the Ambience bus (its volume setting governs it)")
	var wind := AudioServer.get_bus_index(WeatherAudio.WIND_BUS)
	t.check(wind > outside and AudioServer.get_bus_send(wind) == WeatherAudio.OUTSIDE_BUS,
		"[buses] a Wind bus (I022) feeds the Outside bus: muffled below deck, under Ambience, with its own volume")
	var sfx := AudioServer.get_bus_index(&"SFX")
	t.check(AudioServer.get_bus_effect_count(sfx) == 0 and AudioServer.get_bus_send(sfx) == &"Master",
		"[buses] the SFX bus is unfiltered and goes straight out (later alarms stay clear inside and out)")


func _sample(classification: StringName, thunder_active := false, thunder_possible := false) -> WeatherSample:
	var s := WeatherSample.new()
	s.classification = classification
	s.thunder_active = thunder_active
	s.thunder_possible = thunder_possible
	return s


func _test_rain_rule() -> void:
	t.check(WeatherAudio.rain_level(_sample(WeatherModel.CLASS_FAIR)) == 0.0
		and WeatherAudio.rain_level(_sample(WeatherModel.CLASS_STRONG_WIND)) == 0.0
		and WeatherAudio.rain_level(_sample(WeatherModel.CLASS_THUNDER_RISK, false, true)) == 0.25
		and WeatherAudio.rain_level(_sample(WeatherModel.CLASS_GALE)) == 0.6
		and WeatherAudio.rain_level(_sample(WeatherModel.CLASS_THUNDERSTORM, true, true)) == 1.0,
		"[rain] dry in fair weather and plain wind, showers in thunderstorm risk, steady in gales, heavy in thunderstorms")


func _test_loops_and_muffling() -> void:
	var audio: WeatherAudio = app.weather_audio
	await _show(SessionState.AREA_EXTERIOR)
	app.update_weather_audio()
	await t.frames(2)
	t.check(AudioManager.is_loop_playing(WeatherAudio.WIND_LOOP) and AudioManager.is_loop_playing(WeatherAudio.WATER_LOOP)
		and not AudioManager.is_loop_playing(WeatherAudio.RAIN_LOOP) and not app.is_storm_audio_playing(),
		"[loops] a 12 kn breeze underway: wind and water, no rain, no storm wind")
	var breeze_db := AudioManager.get_loop_target_db(WeatherAudio.WIND_LOOP)
	t.check(AudioManager.get_loop_player(WeatherAudio.WIND_LOOP).bus == WeatherAudio.WIND_BUS
		and AudioManager.get_loop_player(WeatherAudio.WATER_LOOP).bus == WeatherAudio.OUTSIDE_BUS,
		"[loops] the wind on its own Wind bus (I022), the water on the Outside bus")
	# A gale: stronger wind sound, the storm wind and rain.
	WeatherFixtures.use([WeatherFixtures.gale("atmosphere_gale", GameSession.get_vessel_position(), 120.0, 40.0,
		GameSession.get_game_time() - 3600.0, 72.0)], true)
	t.set_wind(270.0, 12.0)
	app.update_weather_audio()
	await t.frames(2)
	t.check(app.is_storm_audio_playing() and AudioManager.is_loop_playing(WeatherAudio.RAIN_LOOP)
		and AudioManager.get_loop_target_db(WeatherAudio.WIND_LOOP) > breeze_db,
		"[loops] in a gale: louder wind, the strong-wind loop and rain (%.1f dB → %.1f dB)" % [breeze_db, AudioManager.get_loop_target_db(WeatherAudio.WIND_LOOP)])
	# Below deck: muffled; back on deck: open.
	await _show(SessionState.AREA_INTERIOR)
	app.update_weather_audio()
	await t.get_tree().create_timer(0.9).timeout
	var filter := AudioServer.get_bus_effect(WeatherAudio.outside_bus_index(), 0) as AudioEffectLowPassFilter
	t.check(audio.get_muffle() > 0.99 and filter.cutoff_hz < 800.0 and AudioServer.get_bus_volume_db(WeatherAudio.outside_bus_index()) < -4.0,
		"[muffle] in the cabin the weather outside is muffled (low-pass %d Hz)" % roundi(filter.cutoff_hz))
	await _show(SessionState.AREA_EXTERIOR, &"from_cabin")
	app.update_weather_audio()
	await t.get_tree().create_timer(0.9).timeout
	t.check(audio.get_muffle() < 0.01 and filter.cutoff_hz > 15000.0, "[muffle] on deck it is clear again")
	WeatherFixtures.clear()


func _test_lightning() -> void:
	var audio: WeatherAudio = app.weather_audio
	var deck := app.router.current_screen as BoatArea
	var lighting := deck.get_lighting()
	# A thunderstorm cell right over the boat: a strike is scheduled.
	WeatherFixtures.use([WeatherFixtures.thunderstorm("atmosphere_cell", GameSession.get_vessel_position(), 6.0, 25.0, 20.0,
		GameSession.get_game_time() - 2.0 * 3600.0, 4.0, 90.0, 0.0)], true)
	t.set_wind(270.0, 12.0)
	var here := Simulation.get_weather_at_vessel()
	print("    thunderstorm at the boat: %s, thunder active %s" % [here.classification, here.thunder_active])
	app.update_weather_audio()
	t.check(audio._strike_in > 0.0 and audio.levels.rain == 1.0, "[lightning] in a thunderstorm a strike is on its way, and it pours")
	# Near: bright, quick thunder; far: dimmer, later.
	var before := lighting.get_ambient_colour().get_luminance()
	audio.strike(1.0)
	var near_delay := audio.get_thunder_delay()
	await t.frames(3)
	var flashed := lighting.get_ambient_colour().get_luminance()
	t.check(flashed > before + 0.05 and audio._thunder_near, "[lightning] a near strike brightens the scene (%.2f → %.2f) and brings near thunder" % [before, flashed])
	await t.get_tree().create_timer(1.0).timeout
	t.check(absf(lighting.get_ambient_colour().get_luminance() - before) < 0.05, "[lightning] the flash is brief")
	audio.strike(12.0)
	t.check(audio.get_thunder_delay() > near_delay + 5.0 and not audio._thunder_near,
		"[thunder] farther storms: later, distant thunder (%.1f s vs %.1f s)" % [audio.get_thunder_delay(), near_delay])
	# Accessibility: no flash at 0 %, a single soft one with Reduce flashing.
	await t.get_tree().create_timer(0.6).timeout
	SettingsManager.set_flash_intensity(0)
	audio.strike(1.0)
	await t.frames(3)
	t.check(absf(lighting.get_ambient_colour().get_luminance() - before) < 0.02 and audio.get_thunder_delay() > 0.0,
		"[access] Lightning flash 0 %: no flash, the thunder still comes")
	SettingsManager.set_flash_intensity(100)
	SettingsManager.set_reduce_flashing(true)
	audio.strike(1.0)
	t.check(audio._flashes.size() == 1, "[access] Reduce flashing: one soft flash instead of a flicker")
	SettingsManager.set_reduce_flashing(false)
	# In the cabin the flash is softer but there.
	await t.get_tree().create_timer(0.6).timeout
	var cabin := await _show(SessionState.AREA_INTERIOR)
	var inside := cabin.get_lighting()
	var calm := inside.get_ambient_colour().get_luminance()
	audio.strike(1.0)
	await t.frames(3)
	t.check(inside.get_ambient_colour().get_luminance() > calm + 0.03, "[lightning] the cabin lights up a little too (protected, not cut off)")
	WeatherFixtures.clear()
	await t.get_tree().create_timer(0.6).timeout


func _test_deck_visuals() -> void:
	t.set_wind(270.0, 18.0)  # from the west: blows east
	var deck := await _show(SessionState.AREA_EXTERIOR, &"from_cabin")
	var visuals := deck.get_weather_visuals()
	await t.get_tree().create_timer(0.8).timeout
	var expected := WeatherVisuals.boat_relative(90.0, Simulation.get_current_heading())
	t.check(visuals.wind_direction.dot(expected) > 0.999 and visuals.get_streak_count() > 3,
		"[cues] wind streaks travel where the wind blows, relative to the boat (%d streaks)" % visuals.get_streak_count())
	t.check(visuals.get_drop_count() == 0, "[cues] no rain in a dry breeze")
	WeatherFixtures.use([WeatherFixtures.gale("atmosphere_gale2", GameSession.get_vessel_position(), 120.0, 40.0,
		GameSession.get_game_time() - 3600.0, 72.0)], true)
	t.set_wind(270.0, 18.0)
	await t.get_tree().create_timer(0.8).timeout
	t.check(visuals.get_drop_count() > 20, "[cues] in a gale it rains on deck (%d drops)" % visuals.get_drop_count())
	await t.screenshot("17_deck_rain_and_wind")
	WeatherFixtures.clear()
