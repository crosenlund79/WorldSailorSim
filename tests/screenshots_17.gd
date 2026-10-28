extends Node
## Iteration 17: renders the thirty review screenshots of Let There Be Light
## into docs/screenshots/iteration17/ (run rendered, e.g. under Xvfb):
##   godot --path . --resolution 1600x900 res://tests/screenshots_17.tscn
##   ... -- --only=cabin        (only the shots whose name contains "cabin")
## Uses the test save folder; never touches the player's saves.

const APP_SCENE := preload("res://src/app/app.tscn")
const OUT := "res://docs/screenshots/iteration17"
const BOATS: Array[StringName] = [&"arctic_wanderer_26", &"starling_33", &"petrel_36", &"halcyon_40"]
const DECK := SessionState.AREA_EXTERIOR
const CABIN := SessionState.AREA_INTERIOR
const MAY_1 := 1777593600.0
const COPENHAGEN := Vector2(12.6, 55.7)

var app: Node
var only := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
	SaveManager.save_dir = "user://test_saves"
	SessionLog.log_dir = "user://test_diagnostics"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _wanted(file_name: String) -> bool:
	return only.is_empty() or only in file_name


func _shot(file_name: String, settle := 6) -> void:
	await _frames(settle)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT.path_join(file_name + ".png")))
	print("shot ", file_name)


func _idle() -> void:
	var guard := 0
	while app.router.is_busy() and guard < 2000:
		guard += 1
		await get_tree().process_frame
	await _frames(3)


func _show(area: StringName, spawn := &"start") -> BoatArea:
	app.modals.clear()
	GameSession.enter_boat_area(area, spawn)
	app._show_current_boat_area()
	await _idle()
	await _frames(4)
	app.toasts.clear()
	app.hud.hide_warning()
	return app.router.current_screen as BoatArea


func _board(id: StringName) -> void:
	var state := GameSession.get_state_snapshot()
	state.vessel_id = id
	GameSession.replace_state(state)


func _set_time(time: float) -> void:
	var state := GameSession.get_state_snapshot()
	state.game_time = time
	GameSession.replace_state(state)


## The next time from `start` when the sun at `geo` is at `elevation`.
func _sun_at(geo: Vector2, start: float, elevation: float, rising: bool) -> float:
	var previous := Daylight.sun_elevation(geo, start)
	for i in range(1, 600):
		var time := start + i * 300.0
		var e := Daylight.sun_elevation(geo, time)
		if (rising and previous < elevation and e >= elevation) or (not rising and previous > elevation and e <= elevation):
			return time
		previous = e
	return start


func _open_chart(dream := false) -> WorldMap:
	app.modals.clear()
	if dream:
		app.open_dream_map()
	else:
		app.open_chart()
	var guard := 0
	while (not (app.router.current_screen is WorldMap) or app.router.is_busy()) and guard < 2000:
		guard += 1
		await get_tree().process_frame
	await _frames(4)
	app.toasts.clear()
	return app.router.current_screen as WorldMap


func _close_chart() -> void:
	(app.router.current_screen as WorldMap).discard_changes()
	app.close_chart()
	await _idle()


func _run() -> void:
	Simulation.auto_advance = false
	app = APP_SCENE.instantiate()
	add_child(app)
	app.router.fade_duration = 0.05
	await _frames(5)
	app.start_new_game()
	await _idle()
	app.toasts.clear()
	var noon := MAY_1 + (12.0 - COPENHAGEN.x / 15.0) * 3600.0
	var dusk := _sun_at(COPENHAGEN, noon, 0.5, false)
	var night := _sun_at(COPENHAGEN, noon, -12.0, false)

	# 1. The world map on the cabin wall (all four boats; the Wing 33 as 01).
	for id in BOATS:
		if _wanted("01_cabin_world_map"):
			_board(id)
			_set_time(noon)
			var cabin := await _show(CABIN)
			var station := cabin.find_child("WorldMap", true, false) as Interactable
			cabin.player.position = station.position
			await _frames(10)
			await _shot("01_cabin_world_map_%s" % id)
	_board(&"starling_33")
	_set_time(noon)

	# 2-6. The Dreamer's Map.
	if _wanted("dream") or _wanted("0"):
		var dream := await _open_chart(true)
		var map := dream.get_map_view()
		map.reset_view()
		await _frames(4)
		if _wanted("02_dream"):
			await _shot("02_dream_map_world")
		for i in 26:
			map.camera.position.x += 600.0 / map.camera.zoom.x
			map._clamp_camera()
			await get_tree().process_frame
		map.center_on_geo(Vector2(160.0, -25.0), 14.0 / map.units_per_degree)
		await _frames(6)
		if _wanted("03_dream"):
			await _shot("03_dream_australia_pacific_after_panning")
		map.center_on_geo(Vector2(180.0, -20.0), 22.0 / map.units_per_degree)
		await _frames(6)
		if _wanted("04_dream"):
			await _shot("04_dream_date_line")
		dream.search_harbours("Papeete")
		dream.select_port(&"papeete")
		map.center_on_geo(Vector2(-149.6, -17.5), 40.0 / map.units_per_degree)
		await _frames(4)
		if _wanted("05_dream"):
			await _shot("05_dream_distant_destination")
		dream.search_harbours("")
		dream.imagine_voyage(&"papeete")
		await _frames(4)
		if _wanted("06_dream"):
			await _shot("06_dream_voyage_daydream")
		await _close_chart()

	# 7, 27, 30. The working chart: regional, a harbour's services, wind time.
	if _wanted("07_") or _wanted("27_") or _wanted("30_"):
		var chart := await _open_chart()
		await _wait(1.0)
		if _wanted("07_"):
			await _shot("07_station_regional_chart")
		chart.select_port(&"skagen")
		await _frames(4)
		if _wanted("27_"):
			await _shot("27_harbour_facilities_preview")
		chart.step_wind_time(2)
		await _wait(1.2)
		if _wanted("30_"):
			await _shot("30_wind_snapshot_controls_forecast")
		await _close_chart()

	# 12-14, 15-18: cabin and deck through the day; the harbour at night.
	for spec in [["12_cabin_noon", CABIN, noon], ["13_cabin_dusk", CABIN, dusk], ["14_cabin_night", CABIN, night],
			["15_deck_noon", DECK, noon], ["16_deck_sunset", DECK, dusk], ["18_harbour_night", DECK, night]]:
		if not _wanted(spec[0]):
			continue
		_set_time(spec[2])
		await _show(spec[1])
		await _wait(0.4)
		await _shot(spec[0])
	if _wanted("25_"):
		_set_time(noon)
		await _show(DECK)
		await _shot("25_fenders_moored")

	# Underway: 8-11, 17, 19-24, 26.
	_set_time(noon)
	t_wind(270.0, 14.0)
	GameSession.plan_route_to(&"las_palmas")
	GameSession.depart()
	Simulation.advance(1800.0)
	var deck := await _show(DECK)
	if _wanted("26_"):
		await _shot("26_fenders_stowed_underway")
	if _wanted("09_") or _wanted("11_"):
		await _shot("09_sailing_panel_and_11_shortcut_help")
	app.open_chartplotter()  # I026: the helm plotter, close up (was a HUD panel)
	await _wait(1.0)
	if _wanted("08_"):
		await _shot("08_cockpit_chartplotter")
	app.modals.clear()
	if _wanted("10_"):
		app.open_action_wheel()
		await _frames(6)
		await _shot("10_action_wheel")
		app.modals.clear()
		await _idle()
	if _wanted("23_"):
		var start := Simulation.get_current_heading()
		await _shot("23a_heading_before_turn")
		for i in 300:
			Simulation.advance(300.0)
			if BoatArea.octant_for(Simulation.get_current_heading()) != BoatArea.octant_for(start):
				break
		await _wait(1.2)
		await _shot("23b_heading_after_turn")
	if _wanted("24_"):
		deck = app.router.current_screen as BoatArea
		var rig := deck.get_node("SailRig") as SailRig
		for f in [0.95, 0.9, 0.85, 0.8, 0.7]:
			deck.player.position = rig.mast.lerp(rig.get_shape().main.clew, f)
			await get_tree().physics_frame
			await get_tree().physics_frame
			if rig.covers(deck.player.position):
				break
		await _wait(0.8)
		await _shot("24_captain_under_the_sail")
		deck.player.position = deck.get_spawn_position(&"start")
	if _wanted("17_"):
		_set_time(_sun_at(GameSession.get_vessel_position(), GameSession.get_game_time(), -12.0, false))
		await _show(DECK)
		await _wait(0.4)
		await _shot("17_deck_night")
	# Weather: rain and wind, lightning outside and from the cabin.
	if _wanted("19_") or _wanted("20_") or _wanted("21_") or _wanted("22_"):
		# At dusk, so a flash shows as it would (by day it barely does).
		_set_time(_sun_at(GameSession.get_vessel_position(), GameSession.get_game_time(), -3.0, false))
		WeatherFixtures.use([WeatherFixtures.thunderstorm("shots_cell", GameSession.get_vessel_position(), 8.0, 25.0, 20.0,
			GameSession.get_game_time() - 2.0 * 3600.0, 4.0, 90.0, 0.0)], true)
		t_wind(250.0, 16.0)
		deck = await _show(DECK)
		app.update_weather_audio()
		await _wait(1.0)
		if _wanted("19_"):
			await _shot("19_rain_and_wind_on_deck")
		if _wanted("21_"):
			app.weather_audio.strike(0.8)
			await _shot("21_lightning_on_deck", 2)
		await _wait(0.8)
		var cabin := await _show(CABIN)
		app.update_weather_audio()
		await _wait(1.0)
		if _wanted("20_"):
			await _shot("20_rain_from_the_cabin")
		if _wanted("22_"):
			app.weather_audio.strike(0.8)
			await _shot("22_lightning_from_the_cabin", 2)
		WeatherFixtures.clear()
		cabin = null
	# 28: the harbours by country; 29: docking.
	if _wanted("28_"):
		app.toggle_captains_log()
		await _frames(4)
		var menu := app.modals.get_top() as CaptainsLogMenu
		menu.show_tab(CaptainsLogMenu.TAB_HARBOURS)
		await _frames(4)
		await _shot("28_harbours_by_country")
		app.modals.clear()
		await _idle()
	if _wanted("29_"):
		await _show(DECK)
		GameSession.change_course(&"gothenburg", [] as Array[Vector2])
		for i in 200:
			Simulation.advance(1800.0)
			if not GameSession.is_underway():
				break
		await _frames(2)
		await get_tree().create_timer(BoatArea.DOCKING_SECONDS * 0.35).timeout
		await _shot("29_docking_arrival", 1)
	get_tree().quit(0)


func t_wind(from_deg: float, speed_kn: float) -> void:
	WindField.get_default().test_override = func(_geo: Vector2, _time: float) -> WindField.Sample:
		return WindField.Sample.make(from_deg, speed_kn)
	Simulation.invalidate_estimates()
