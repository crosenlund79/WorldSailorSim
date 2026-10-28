extends Node
## I026, A World You Can Touch: motion evidence - numbered frames
## (film_NAME_NN.png) that tools/qa/film_strip.py joins into strips:
##   film_npc_day       the same stretch of Copenhagen's quay through a day
##                      (HarbourLife's routines: morning, noon, evening, night)
##   film_npc_walk      people walking and pausing at noon, half a second apart
##   film_cafe          ordering at the café, sitting down, drinking
##   film_shop          walking to the chandlery's door and going in
##   film_instruments   paging the Modern Cruiser's displays
##   film_focus         the logbook brought close (FocusFrame's grow-in)
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1600x900 res://tests/screenshots_i026_motion.tscn -- [--out=DIR] [--films=a,b]
## Uses the test save and settings files; never touches the player's own.

const APP_SCENE := preload("res://src/app/app.tscn")

var app: Node
var out := "user://i026_motion"
var only: Array[String] = []


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	SettingsManager.settings_path = "user://test_settings.cfg"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--films="):
			for s in a.trim_prefix("--films=").split(",", false):
				only.append(s)
	_run.call_deferred()


func _wanted(name: String) -> bool:
	return only.is_empty() or name in only


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _idle() -> void:
	var guard := 0
	while app.router.is_busy() and guard < 2000:
		guard += 1
		await get_tree().process_frame
	await _frames(6)


func _frame(film: String, index: int) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/film_%s_%02d.png" % [out, film, index])


## Moored in `port_id` at local solar hour `hour` on a Wednesday.
func _moor_in(port_id: StringName, hour: float) -> void:
	var state := GameSession.get_state_snapshot()
	state.location_id = port_id
	state.vessel_status = SessionState.STATUS_MOORED
	state.vessel_position = PortCatalog.get_default().get_port(port_id).get_geo_position()
	state.voyage = null
	var day_start := floorf(state.game_time / 86400.0) * 86400.0
	state.game_time = day_start + fposmod(hour - state.vessel_position.x / 15.0, 24.0) * 3600.0
	while BusinessHours.local_weekday(port_id, state.game_time) != 3:
		state.game_time += 86400.0
	GameSession.replace_state(state)
	UiTheme.set_blend(UiTheme._target_blend(), true)


func _quay() -> HarbourFront:
	app.modals.clear()
	app.toasts.clear()
	if not app.router.current_screen is HarbourFront:
		GameSession.enter_boat_area(SessionState.AREA_EXTERIOR, &"from_boatyard")
		app._show_current_boat_area()
		await _idle()
		app.open_quay()
		await _idle()
	var front := app.router.current_screen as HarbourFront
	front.life.rebuild()
	front.refresh()
	front._initialised = false
	front._update_light(0.0)
	UiTheme.set_blend(UiTheme._target_blend(), true)
	return front


func _stand(front: HarbourFront, at: Vector2) -> void:
	front.player.position = at
	front.player.set_facing(Vector2.UP)
	front.camera.position.x = front._camera_x(at.x)
	await get_tree().physics_frame
	await _frames(3)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	Simulation.auto_advance = false
	WindField.get_default().test_override = func(_geo: Vector2, _time: float) -> WindField.Sample:
		return WindField.Sample.make(220.0, 8.0)
	WeatherModel.get_default().clear_cache()
	app = APP_SCENE.instantiate()
	add_child(app)
	await _frames(12)
	app.start_new_game()
	await _idle()
	Simulation.auto_advance = true
	GameSession.set_time_scale(1)

	if _wanted("npc_day"):
		var hours := [7.2, 9.0, 11.0, 13.0, 15.5, 17.5, 19.5, 22.0]
		for i in hours.size():
			_moor_in(&"copenhagen", hours[i])
			var front := await _quay()
			await _stand(front, front.layout.door_station(QuayLayout.CAFE) + Vector2(0, 180))
			await get_tree().create_timer(2.5).timeout
			await _frame("npc_day", i)
	if _wanted("npc_walk"):
		_moor_in(&"copenhagen", 12.0)
		var front := await _quay()
		await _stand(front, front.layout.door_station(QuayLayout.CAFE) + Vector2(0, 180))
		await get_tree().create_timer(3.0).timeout
		for i in 8:
			await get_tree().create_timer(0.5).timeout
			await _frame("npc_walk", i)
	if _wanted("cafe"):
		_moor_in(&"copenhagen", 13.0)
		var front := await _quay()
		await _stand(front, front.layout.door_station(QuayLayout.CAFE) + Vector2(0, 60))
		await get_tree().create_timer(1.0).timeout
		await _frame("cafe", 0)
		front._on_interacted(front.get_station(QuayLayout.CAFE), front.player)
		await _frames(12)
		await _frame("cafe", 1)
		app._on_cafe_order()
		for i in 6:
			await get_tree().create_timer(0.8).timeout
			front.camera.position.x = front._camera_x(front.player.position.x)
			await _frame("cafe", 2 + i)
		front.stand_up()
	if _wanted("shop"):
		_moor_in(&"copenhagen", 11.0)
		var front := await _quay()
		var door := front.layout.door_station(QuayLayout.CHANDLERY)
		await _stand(front, door + Vector2(260, 30))
		# Walked at the Captain's pace (positions set per frame: synthetic
		# input is not read in this capture).
		for i in 5:
			var from := front.player.position
			var to := door + Vector2(260 - 65 * (i + 1), 30 - 5 * (i + 1))
			front.player.set_facing((to - from).normalized())
			for f in 12:
				front.player.position = from.lerp(to, (f + 1) / 12.0)
				await get_tree().physics_frame
			await _frame("shop", i)
		await _stand(front, door + Vector2(0, 8))
		await _frame("shop", 5)
		front._on_interacted(front.get_station(QuayLayout.CHANDLERY), front.player)
		for i in 3:
			await get_tree().create_timer(0.07).timeout
			await _frame("shop", 6 + i)
		app.modals.clear()
	if _wanted("instruments"):
		app.modals.clear()
		var state := GameSession.get_state_snapshot()
		state.funds = 20000
		GameSession.replace_state(state)
		GameSession.buy_instrument_package(InstrumentPackage.MODERN)
		GameSession.enter_boat_area(SessionState.AREA_EXTERIOR, &"start")
		app._show_current_boat_area()
		await _idle()
		var view: InstrumentView = app.open_instruments()
		await get_tree().create_timer(0.6).timeout
		await _frame("instruments", 0)
		for i in 7:
			var key := view.get_key("next_%d" % (i % 2))
			if key:
				key.pressed.emit()
			await get_tree().create_timer(0.3).timeout
			await _frame("instruments", 1 + i)
		app.modals.clear()
	if _wanted("focus"):
		app.modals.clear()
		GameSession.enter_boat_area(SessionState.AREA_INTERIOR, &"from_deck")
		app._show_current_boat_area()
		await _idle()
		await _frame("focus", 0)
		app.open_cabin_object(CabinObject.LOGBOOK)
		for i in 6:
			await get_tree().create_timer(0.04).timeout
			await _frame("focus", 1 + i)
		app.modals.clear()
	print("I026 MOTION DONE")
	get_tree().quit()
