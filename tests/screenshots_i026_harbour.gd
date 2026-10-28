extends Node
## I026 stage 02, living harbours: rendered evidence of the quay
## (HarbourFront) - the separate storefronts, their entrances and counters,
## opening hours on the doors, the people at different hours, the café, the
## noticeboard and regional variants.
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1600x900 res://tests/screenshots_i026_harbour.tscn -- [--out=DIR] [--shots=a,b]
## Uses the test save and settings files; never touches the player's own.

const APP_SCENE := preload("res://src/app/app.tscn")

var app: Node
var out := "res://docs/screenshots/i026/harbour"
var only: Array[String] = []


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	SettingsManager.settings_path = "user://test_settings.cfg"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--shots="):
			for s in a.trim_prefix("--shots=").split(",", false):
				only.append(s)
	_run.call_deferred()


func _wanted(name: String) -> bool:
	if only.is_empty():
		return true
	for s in only:
		if name.begins_with(s):
			return true
	return false


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _idle() -> void:
	var guard := 0
	while app.router.is_busy() and guard < 2000:
		guard += 1
		await get_tree().process_frame
	await _frames(6)


## Moored in `port_id` at local solar hour `hour` (a weekday).
func _moor_in(port_id: StringName, hour: float) -> void:
	var state := GameSession.get_state_snapshot()
	state.location_id = port_id
	state.vessel_status = SessionState.STATUS_MOORED
	state.vessel_position = PortCatalog.get_default().get_port(port_id).get_geo_position()
	state.voyage = null
	var day_start := floorf(state.game_time / 86400.0) * 86400.0
	state.game_time = day_start + fposmod(hour - state.vessel_position.x / 15.0, 24.0) * 3600.0
	# A weekday (Wednesday) on the harbour's solar time.
	while BusinessHours.local_weekday(port_id, state.game_time) != 3:
		state.game_time += 86400.0
	GameSession.replace_state(state)
	UiTheme.set_blend(UiTheme._target_blend(), true)


func _quay() -> HarbourFront:
	app.modals.clear()
	app.toasts.clear()
	var current := app.router.current_screen as HarbourFront
	if current and current.port_id != GameSession.get_location_id():
		app.leave_quay()  # another harbour: back aboard, then up its own quay
		await _idle()
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


## Puts the Captain at `at` (quay coordinates), facing up, the camera there.
func _stand(front: HarbourFront, at: Vector2, facing := Vector2.UP) -> void:
	front.player.position = at
	front.player.set_facing(facing)
	front.camera.position.x = front._camera_x(at.x)
	for node in front.get_companion_nodes():
		node.position = at + node._offset()
	await get_tree().physics_frame
	await get_tree().physics_frame
	await _frames(3)


func _shot(name: String, settle := 0.5) -> void:
	await get_tree().create_timer(settle).timeout
	await _frames(3)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("SHOT %s" % name)


func _door(front: HarbourFront, business: StringName) -> Vector2:
	return front.layout.door_station(business)


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

	# The deck: the pontoon's walkway up to the quay.
	if _wanted("01"):
		_moor_in(&"copenhagen", 11.0)
		app.modals.clear()
		GameSession.enter_boat_area(SessionState.AREA_EXTERIOR, &"from_boatyard")
		app._show_current_boat_area()
		await _idle()
		var deck := app.router.current_screen as BoatArea
		var walkway := deck.get_walkway()
		deck.player.position = walkway.position + Vector2(0, -20)
		await _frames(30)
		await _shot("01_pontoon_walkway_to_the_quay", 1.5)

	_moor_in(&"copenhagen", 11.0)
	var front := await _quay()
	if _wanted("02"):
		await _stand(front, front.layout.arrival_point())
		await _shot("02_quay_copenhagen_arrival", 2.0)
	if _wanted("03"):
		await _stand(front, _door(front, QuayLayout.BOATYARD) + Vector2(-60, 10))
		await _shot("03_boatyard_highlighted")
	if _wanted("04"):
		await _stand(front, _door(front, QuayLayout.CHANDLERY) + Vector2(0, 8))
		await _shot("04_chandlery_entrance")
	if _wanted("05"):
		await _stand(front, _door(front, QuayLayout.SAIL_LOFT) + Vector2(0, 8))
		await _shot("05_sail_loft_entrance")
	if _wanted("06"):
		await _stand(front, _door(front, QuayLayout.GROCERY) + Vector2(0, 8))
		await _shot("06_grocery_entrance")
	if _wanted("07"):
		await _stand(front, _door(front, QuayLayout.FISHMONGER) + Vector2(0, 8))
		await _shot("07_fishmonger_stall")
	if _wanted("08"):
		await _stand(front, _door(front, QuayLayout.CHANDLERY) + Vector2(0, 8))
		front._on_interacted(front.get_station(QuayLayout.CHANDLERY), front.player)
		await _frames(4)
		await _shot("08_chandlery_counter")
		app.modals.clear()
	if _wanted("09"):
		await _stand(front, _door(front, QuayLayout.BOATYARD) + Vector2(0, 8))
		front._on_interacted(front.get_station(QuayLayout.BOATYARD), front.player)
		await _frames(4)
		await _shot("09_boatyard_counter")
		app.modals.clear()
	if _wanted("10"):
		await _stand(front, _door(front, QuayLayout.GROCERY) + Vector2(0, 8))
		front._on_interacted(front.get_station(QuayLayout.GROCERY), front.player)
		await _frames(4)
		await _shot("10_grocery_counter")
		app.modals.clear()
	if _wanted("11"):
		await _stand(front, front.layout.noticeboard + Vector2(0, 40))
		await _shot("11a_noticeboard")
		front._on_interacted(front.get_station(QuayLayout.NOTICEBOARD), front.player)
		await _frames(4)
		await _shot("11b_noticeboard_read")
		app.modals.clear()
	if _wanted("12"):
		await _stand(front, _door(front, QuayLayout.CAFE) + Vector2(0, 150))
		await _shot("12_npcs_walking_midday", 6.0)

	# Morning: the café opens early, the chandlery and the sail loft are shut.
	if _wanted("13") or _wanted("14"):
		_moor_in(&"copenhagen", 7.6)
		front = await _quay()
		if _wanted("13"):
			await _stand(front, _door(front, QuayLayout.CHANDLERY) + Vector2(0, 8))
			await _shot("13_closed_chandlery_morning", 1.0)
			front._on_interacted(front.get_station(QuayLayout.CHANDLERY), front.player)
			await _frames(6)
			await _shot("13b_wait_until_it_opens")
			app.modals.clear()
		if _wanted("14"):
			await _stand(front, _door(front, QuayLayout.CAFE) + Vector2(0, 200))
			await _shot("14_morning_activity", 4.0)

	# The café at noon: customers, the Captain with a coffee, a companion.
	if _wanted("15") or _wanted("16") or _wanted("17"):
		_moor_in(&"copenhagen", 13.0)
		front = await _quay()
		if _wanted("15"):
			await _stand(front, _door(front, QuayLayout.CAFE) + Vector2(0, 260))
			await _shot("15_cafe_with_customers", 3.0)
		if _wanted("16") or _wanted("17"):
			if _wanted("17"):
				# A companion ashore with the Captain (a Ragdoll named Kiwi).
				app.start_new_game(&"cat", Difficulty.STANDARD, "Kiwi")
				await _idle()
				_moor_in(&"copenhagen", 13.0)
				for c in GameSession.get_companions():
					GameSession.set_companion_area(CompanionState.AREA_SHORE, 0, c.id)
				front = await _quay()
			await _stand(front, _door(front, QuayLayout.CAFE) + Vector2(0, 60))
			front._on_interacted(front.get_station(QuayLayout.CAFE), front.player)
			await _frames(4)
			await _shot("16a_cafe_counter")
			app._on_cafe_order()
			await _frames(4)
			front.camera.position.x = front._camera_x(front.player.position.x)
			await _shot("16_captain_having_coffee" if not _wanted("17") else "17_pet_resting_at_cafe", 5.0)
			front.stand_up()

	# Evening: the shops closing, a shopkeeper locking up, lit windows.
	if _wanted("18"):
		var close := BusinessHours.hours(QuayLayout.CHANDLERY, &"copenhagen").y
		_moor_in(&"copenhagen", close + 0.1)
		front = await _quay()
		await _stand(front, _door(front, QuayLayout.CHANDLERY) + Vector2(140, 120))
		await _shot("18_evening_shopkeeper_locking_up", 2.5)
	if _wanted("19"):
		_moor_in(&"copenhagen", 21.6)
		front = await _quay()
		await _stand(front, front.layout.arrival_point() + Vector2(300, -80))
		await _shot("19_night_quay", 2.0)

	# Regional variants.
	for entry in [[&"svendborg", "20_nordic_svendborg"], [&"naples", "21_mediterranean_naples"], [&"hydra", "22_mediterranean_hydra"],
			[&"castries", "23_tropical_castries"], [&"dingle", "24_atlantic_dingle_small"], [&"lohals", "25_small_lohals"]]:
		if not _wanted(String(entry[1]).substr(0, 2)):
			continue
		_moor_in(entry[0], 10.5)
		front = await _quay()
		await _stand(front, front.layout.arrival_point() + Vector2(-500, -120))
		await _shot(entry[1], 3.0)
	print("I026 HARBOUR SHOTS DONE")
	get_tree().quit()

