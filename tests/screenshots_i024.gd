extends Node
## I024, The Company We Keep: rendered evidence from the running game - the
## three companions aboard, the parrot perched and flying, a companion
## ashore, waking with the companion by the berth, the Captain talking on a
## long passage, and the cabin laptop (on the table, open, the achievements
## with locked badges, a detail with when and where, the postcard composer,
## a category). Run rendered (Xvfb + software OpenGL is fine):
##   xvfb-run godot --path . --rendering-driver opengl3 --resolution 1600x900 \
##     res://tests/screenshots_i024.tscn -- --out=DIR [--only=PREFIX]
## Uses the test save and settings files; never touches the player's own.

const APP_SCENE := preload("res://src/app/app.tscn")

var app: Node
var out := "res://docs/screenshots/i024"
var only := ""


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	SettingsManager.settings_path = "user://test_settings.cfg"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--only="):
			only = a.trim_prefix("--only=")
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
	await get_tree().create_timer(0.5).timeout
	await _frames(3)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, file_name])
	print("SHOT %s" % file_name)


## The same frame, a closer look: the part of the screen around `subject`
## (a node in the world), enlarged 2x - so a small animal can be seen.
func _closeup(file_name: String, subject: Node2D, size := Vector2(520, 300), frame: Image = null) -> void:
	if frame == null:
		await RenderingServer.frame_post_draw
	var image := frame if frame else get_viewport().get_texture().get_image()
	# Canvas coordinates are in the project's base size (1920 × 1080); the
	# image is the window's.
	var at := subject.get_global_transform_with_canvas().origin * Vector2(image.get_size()) / get_viewport().get_visible_rect().size
	var rect := Rect2i(Vector2i((at - size * 0.5).clamp(Vector2.ZERO, Vector2(image.get_size()) - size)), Vector2i(size))
	var crop := image.get_region(rect)
	crop.resize(rect.size.x * 2, rect.size.y * 2, Image.INTERPOLATE_LANCZOS)
	crop.save_png("%s/%s.png" % [out, file_name])
	print("SHOT %s" % file_name)


func _set_local_hour(hour: float) -> void:
	var state := GameSession.get_state_snapshot()
	var geo := GameSession.get_vessel_position()
	var day_start := floorf(state.game_time / 86400.0) * 86400.0
	state.game_time = day_start + fposmod(hour - geo.x / 15.0, 24.0) * 3600.0
	GameSession.replace_state(state)
	UiTheme.set_blend(UiTheme._target_blend(), true)


func _show(area: StringName, spawn: StringName = &"start") -> BoatArea:
	app.modals.clear()
	GameSession.enter_boat_area(area, spawn)
	app._show_current_boat_area()
	await _idle()
	var screen := app.router.current_screen as BoatArea
	var lighting := screen.get_node_or_null("Lighting")
	if lighting:
		lighting._weather_at = -INF
		lighting.update_now()
	app.toasts.clear()
	return screen


func _companion() -> ShipCompanion:
	return (app.router.current_screen as Node).find_child("Companion", false, false) as ShipCompanion


## Looks closer at `at` (the cabin camera).
func _look_at(area: BoatArea, at: Vector2, zoom := 1.9) -> void:
	var camera := area.get_node_or_null(^"Camera2D") as Camera2D
	if camera:
		camera.position = at
		camera.zoom = Vector2(zoom, zoom)


func _new_game(kind: StringName, name: String, gender: StringName) -> void:
	app.modals.clear()
	app.start_new_game(kind, Difficulty.STANDARD, name, gender)
	await _idle()
	app.modals.clear()


func _sail_to(port: StringName) -> void:
	GameSession.plan_route_to(port)
	GameSession.depart()
	var guard := 40
	while GameSession.is_underway() and guard > 0:
		guard -= 1
		Simulation.advance(12.0 * 3600.0, true)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	Simulation.auto_advance = false
	WindField.get_default().test_override = func(_geo: Vector2, _time: float) -> WindField.Sample:
		return WindField.Sample.make(220.0, 11.0)
	WeatherFixtures.use([])
	app = APP_SCENE.instantiate()
	add_child(app)
	await _frames(12)
	SettingsManager.set_ui_light(SettingsManager.UI_LIGHT_AUTO)
	# 1. The Ragdoll beside the Captain.
	if _wanted("01"):
		await _new_game(CompanionState.KIND_CAT, "Snowy", CompanionState.GENDER_FEMALE)
		_set_local_hour(11.0)
		var cabin := await _show(SessionState.AREA_INTERIOR, &"from_deck")
		var cat := _companion()
		cabin.player.position = cat.position + Vector2(-46, 18)
		cabin.player.set_facing(cat.position - cabin.player.position)
		cat.set_pose(CompanionVisualSet.POSE_SIT, 999.0)
		_look_at(cabin, cat.position + Vector2(-20, 0), 2.2)
		await _frames(20)
		await _shot("01_ragdoll_beside_captain")
		await _closeup("01b_ragdoll_beside_captain_closeup", cat)
	# 2. The Pug aboard, on deck.
	if _wanted("02"):
		await _new_game(CompanionState.KIND_DOG, "Fido", CompanionState.GENDER_MALE)
		_set_local_hour(10.0)
		await _show(SessionState.AREA_EXTERIOR, &"start")
		GameSession.set_companion_area(CompanionState.AREA_DECK, 1)
		await get_tree().create_timer(6.0).timeout
		_companion().set_pose(CompanionVisualSet.POSE_TAIL_WAG, 999.0)
		await _shot("02_pug_aboard")
		await _closeup("02b_pug_aboard_closeup", _companion())
	# 3, 4. The parrot perched, and flying between perches.
	if _wanted("03") or _wanted("04"):
		await _new_game(CompanionState.KIND_PARROT, "Kiwi", CompanionState.GENDER_FEMALE)
		_set_local_hour(14.0)
		var cabin := await _show(SessionState.AREA_INTERIOR, &"from_deck")
		var bird := _companion()
		_look_at(cabin, bird.position, 2.4)
		bird.set_pose(CompanionVisualSet.POSE_RESTING, 999.0)
		await _frames(10)
		if _wanted("03"):
			await _shot("03_parrot_perched")
			await _closeup("03b_parrot_perched_closeup", bird, Vector2(360, 220))
		if _wanted("04"):
			var to := bird.get_spot_position(&"settee")
			if to.distance_to(bird.position) < 80.0:
				to = bird.get_spot_position(&"v_berth")
			_look_at(cabin, bird.position.lerp(to, 0.5), 1.7)
			bird._start_walk(bird.position, to)
			await get_tree().create_timer(clampf(bird.position.distance_to(to) / 110.0 * 0.5, 0.4, 2.0)).timeout
			await RenderingServer.frame_post_draw
			var frame := get_viewport().get_texture().get_image()
			frame.save_png("%s/%s.png" % [out, "04_parrot_in_flight"])
			print("SHOT 04_parrot_in_flight")
			await _closeup("04b_parrot_in_flight_closeup", bird, Vector2(360, 220), frame)
	# 5. A companion ashore with the Captain.
	if _wanted("05"):
		await _new_game(CompanionState.KIND_DOG, "Fido", CompanionState.GENDER_MALE)
		_set_local_hour(16.0)
		var deck := await _show(SessionState.AREA_EXTERIOR, &"start")
		var shore := deck.get_shore_access()
		deck.player.position = shore.get_landing_point() + Vector2(-40, 14)
		var guard := 0
		while not GameSession.is_companion_ashore() and guard < 600:
			guard += 1
			await get_tree().process_frame
		var dog := _companion()
		guard = 0
		while dog.is_walking() and guard < 3000:
			guard += 1
			dog._process(0.1)  # its walk, without waiting for slow software rendering
		dog.set_pose(CompanionVisualSet.POSE_SIT, 999.0)
		await _shot("05_companion_ashore")
		await _closeup("05c_companion_ashore_closeup", dog)
		GameSession.plan_route_to(&"kiel")
		app.request_departure()
		await _frames(6)
		await _shot("05b_departure_waits_for_fido")
		app.modals.clear()
	# 6. Waking, the companion by the berth.
	if _wanted("06"):
		await _new_game(CompanionState.KIND_CAT, "Snowy", CompanionState.GENDER_FEMALE)
		_set_local_hour(22.5)
		await _show(SessionState.AREA_INTERIOR, &"from_deck")
		var found := false
		for night in 6:
			app.sleep_for(9.0)
			await _idle()
			var guard := 0
			while is_instance_valid(app.time_passage) and guard < 3000:  # the night under the black
				guard += 1
				await get_tree().process_frame
			await _frames(4)
			for message in app.toasts.get_messages():
				found = found or message.contains("Snowy") or message.contains("berth")
			if found:
				break
			app.toasts.clear()
		var cabin := app.router.current_screen as BoatArea
		_look_at(cabin, cabin.player.position.lerp(_companion().position, 0.5), 1.8)
		await _shot("06_waking_companion_by_berth", true)
		await _closeup("06b_waking_companion_by_berth_closeup", _companion())
	# 7. Talking on a long passage.
	if _wanted("07"):
		await _new_game(CompanionState.KIND_DOG, "Fido", CompanionState.GENDER_MALE)
		GameSession.plan_route_to(&"reykjavik")
		GameSession.depart()
		Simulation.advance(6.0 * 86400.0, false)
		_set_local_hour(15.0)
		var cabin := await _show(SessionState.AREA_INTERIOR, &"from_deck")
		var dog := _companion()
		dog.set_pose(CompanionVisualSet.POSE_RESTING, 999.0)
		cabin.player.position = dog.position + Vector2(-50, 10)
		_look_at(cabin, dog.position + Vector2(-25, 0), 1.9)
		app.hud.hide_warning()
		app.modals.clear()
		app._talk_voyage_at = GameSession.get_voyage_departed_at()
		app._talk_next_at = 0.0
		app._talk_real_wait = 0.0
		if app.academy:
			app.academy.card.hide()
		# A moment where the Captain says Fido's name and Fido answers.
		for i in 40:
			app._talk_count = i
			app._talk_said.clear()
			app.toasts.clear()
			dog.set_pose(CompanionVisualSet.POSE_RESTING, 999.0)
			app._update_passage_talk(0.1)
			var said: Array = app.toasts.get_messages()
			if said.size() > 0 and String(said[0]).contains("Fido") and String(said[0]).contains("\n"):
				break
			app._talk_next_at = 0.0
			app._talk_real_wait = 0.0
		await _frames(10)
		await _shot("07_long_passage_talk", true)
	# 8-13. The laptop.
	if _wanted("08") or _wanted("09") or _wanted("1"):
		await _new_game(CompanionState.KIND_CAT, "Snowy", CompanionState.GENDER_FEMALE)
		_sail_to(&"kiel")
		_sail_to(&"copenhagen")
		_set_local_hour(20.5)
		# A sustained hour under sail, for the history.
		var now := GameSession.get_game_time() - 14 * 300.0
		for i in 14:
			GameSession.note_sailing(now + i * 300.0, now + (i + 1) * 300.0, 7.4, true)
		var cabin := await _show(SessionState.AREA_INTERIOR, &"from_deck")
		var laptop_prop := cabin.get_laptop()
		var station := cabin.get_node(^"Layout/Stations/Work") as Node2D
		cabin.player.position = station.position + Vector2(0, 8)
		cabin.player.set_facing(laptop_prop.position - cabin.player.position)
		_look_at(cabin, laptop_prop.position + Vector2(0, 10), 2.6)
		await _frames(10)
		if _wanted("08"):
			await _shot("08_laptop_on_cabin_table")
			await _closeup("08b_laptop_on_cabin_table_closeup", laptop_prop, Vector2(360, 220))
		var laptop: LaptopView = app.open_laptop()
		await _frames(10)
		if _wanted("09"):
			await _shot("09_laptop_open_home")
		laptop.show_app(LaptopView.APP_ACHIEVEMENTS)
		await _frames(6)
		if _wanted("10"):
			await _shot("10_achievements_locked_grey")
		var ids := laptop.get_shown_ids()
		laptop.select_achievement(ids[0])
		await _frames(6)
		if _wanted("11"):
			await _shot("11_achievement_detail")
		laptop.show_app(LaptopView.APP_PUBLICATIONS)
		laptop.open_postcards()
		await _frames(10)
		if _wanted("12"):
			await _shot("12_laptop_postcard_composer")
		laptop.show_app(LaptopView.APP_ACHIEVEMENTS)
		laptop.set_category("voyages")
		await _frames(6)
		if _wanted("13"):
			await _shot("13_achievement_category_voyages")
		laptop.show_app(LaptopView.APP_HISTORY)
		await _frames(6)
		if _wanted("14"):
			await _shot("14_laptop_voyage_history")
		SettingsManager.set_language(&"da")
		laptop.show_app(LaptopView.APP_ACHIEVEMENTS)
		await _frames(8)
		if _wanted("15"):
			await _shot("15_laptop_achievements_danish")
		SettingsManager.set_language(&"en")
	print("I024 SHOTS DONE")
	get_tree().quit()
