extends Node
## Operation Real Horizon: rendered evidence of the new look in the running
## game - title screen, harbour arrival, deck and cabin, under way in fair
## weather, fresh breeze and a gale, dusk and night, the chart and the main
## panels. Run rendered (Xvfb + software OpenGL is fine):
##   xvfb-run godot --path . --rendering-driver opengl3 --resolution 1600x900 \
##     res://tests/screenshots_horizon.tscn -- --out=DIR [--only=PREFIX] [--vessel=ID]
## Uses the test save and settings files; never touches the player's own.

const APP_SCENE := preload("res://src/app/app.tscn")

var app: Node
var out := "res://docs/screenshots/real_horizon"
var only := ""
var vessel := ""


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	SettingsManager.settings_path = "user://test_settings.cfg"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--only="):
			only = a.trim_prefix("--only=")
		elif a.begins_with("--vessel="):
			vessel = a.trim_prefix("--vessel=")
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _idle() -> void:
	var guard := 0
	while app.router.is_busy() and guard < 2000:
		guard += 1
		await get_tree().process_frame
	await _frames(6)


func _wanted(file_name: String) -> bool:
	return only == "" or file_name.begins_with(only)


func _shot(file_name: String, keep_toasts := false) -> void:
	if not keep_toasts:
		app.toasts.clear()
	# Let the sea and light ease to the scene's weather.
	await get_tree().create_timer(0.6).timeout
	await _frames(4)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, file_name])
	print("SHOT %s" % file_name)


func _set_local_hour(hour: float) -> void:
	var state := GameSession.get_state_snapshot()
	var geo := GameSession.get_vessel_position()
	var day_start := floorf(state.game_time / 86400.0) * 86400.0
	state.game_time = day_start + fposmod(hour - geo.x / 15.0, 24.0) * 3600.0
	GameSession.replace_state(state)
	UiTheme.set_blend(UiTheme._target_blend(), true)


func _wind(kn: float) -> void:
	WindField.get_default().test_override = func(_geo: Vector2, _time: float) -> WindField.Sample:
		return WindField.Sample.make(220.0, kn)
	WeatherModel.get_default().clear_cache()


func _gale(on: bool) -> void:
	if on:
		var now := GameSession.get_game_time()
		WeatherFixtures.use([WeatherFixtures.gale("horizon_gale", GameSession.get_vessel_position(), 300.0, 42.0, now - 7200.0, 96.0)])
	else:
		WeatherFixtures.use([])


func _show(area: StringName) -> BoatArea:
	app.modals.clear()
	GameSession.enter_boat_area(area, &"start")
	app._show_current_boat_area()
	await _idle()
	var screen := app.router.current_screen as BoatArea
	var lighting := screen.get_node_or_null("Lighting")
	if lighting:
		lighting._weather_at = -INF
		lighting.update_now()
	var sea := screen.get_node_or_null("SeaSurface") as SeaSurface
	if sea:
		sea._sample()
		for key: String in sea._target:
			sea.set(key, sea._target[key])
	app.toasts.clear()
	return screen


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	Simulation.auto_advance = false
	_wind(11.0)
	WeatherFixtures.use([])
	app = APP_SCENE.instantiate()
	add_child(app)
	await _frames(12)
	SettingsManager.set_ui_light(SettingsManager.UI_LIGHT_AUTO)
	if _wanted("00"):
		await _shot("00_title")
	app.start_new_game()
	await _idle()
	if vessel != "":
		var state := GameSession.get_state_snapshot()
		state.vessel_id = StringName(vessel)
		GameSession.replace_state(state)
	# Harbour by day.
	_set_local_hour(11.0)
	if _wanted("01"):
		await _show(SessionState.AREA_EXTERIOR)
		await _shot("01_harbour_deck_day")
	if _wanted("02"):
		await _show(SessionState.AREA_INTERIOR)
		await _shot("02_cabin_day")
	if _wanted("03"):
		GameSession.plan_route_to(&"kiel")
		app.open_chart()
		await _idle()
		await _frames(10)
		await _shot("03_chart")
		app.close_chart()
		await _idle()
	# Under way: a fresh morning, a breeze in the afternoon, a gale.
	GameSession.plan_route_to(&"kiel")
	GameSession.depart()
	Simulation.advance(1800.0)
	for spec in [["04_underway_light_air", 9.0, 5.0, false], ["05_underway_fresh_breeze", 15.0, 16.0, false],
			["06_underway_gale", 14.0, 0.0, true], ["07_underway_dusk", 20.6, 9.0, false], ["08_underway_night", 23.5, 9.0, false]]:
		if not _wanted(spec[0]):
			continue
		_set_local_hour(spec[1])
		if spec[3]:
			_gale(true)
		else:
			_gale(false)
			_wind(spec[2])
		await _show(SessionState.AREA_EXTERIOR)
		await _shot(spec[0])
	_gale(false)
	_wind(11.0)
	if _wanted("09"):
		_set_local_hour(22.5)
		await _show(SessionState.AREA_INTERIOR)
		await _shot("09_cabin_night")
	if _wanted("10"):
		_set_local_hour(13.0)
		await _show(SessionState.AREA_EXTERIOR)
		app.open_sail_trim()
		await _frames(8)
		await _shot("10_sail_trim")
		app.modals.clear()
	# Arrival in a harbour.
	if _wanted("11"):
		var state := GameSession.get_state_snapshot()
		state.location_id = &"kiel"
		state.vessel_status = SessionState.STATUS_MOORED
		GameSession.replace_state(state)
		_set_local_hour(16.0)
		await _show(SessionState.AREA_EXTERIOR)
		await _shot("11_harbour_arrival_kiel")
	print("HORIZON SHOTS DONE")
	get_tree().quit()
