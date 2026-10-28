extends Node
## I021, A Wider, Warmer World: rendered evidence of every harbour look and
## of the special harbours (the view beyond the quay at a harbour of each
## look and at each special harbour, the arrival card, and the special mark
## on the navigation chart by day and by night and on the Dreamer's Map).
##   xvfb-run godot --path . --rendering-driver opengl3 --resolution 1600x900 \
##     res://tests/screenshots_i021.tscn -- --out=DIR

const APP_SCENE := preload("res://src/app/app.tscn")
## A harbour of each look (and each special harbour, which shows its own view).
const HARBOURS: Array[StringName] = [&"svolvaer", &"marstal", &"dingle", &"naples", &"mykonos", &"zanzibar", &"dakar",
	&"bora_bora", &"horta", &"copenhagen", &"valletta", &"symi", &"essaouira", &"lunenburg", &"st_helena"]

var app: Node
var out := "res://docs/screenshots/i021"


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	SettingsManager.settings_path = "user://test_settings.cfg"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
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


func _shot(file_name: String, keep_toasts := false) -> void:
	if not keep_toasts:
		app.toasts.clear()
	await _frames(4)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, file_name])
	print("SHOT %s" % file_name)


func _moor_in(port_id: StringName, hour: float) -> void:
	var state := GameSession.get_state_snapshot()
	state.location_id = port_id
	state.vessel_status = SessionState.STATUS_MOORED
	state.vessel_position = PortCatalog.get_default().get_port(port_id).get_geo_position()
	state.voyage = null
	var day_start := floorf(state.game_time / 86400.0) * 86400.0
	state.game_time = day_start + fposmod(hour - state.vessel_position.x / 15.0, 24.0) * 3600.0
	GameSession.replace_state(state)
	UiTheme.set_blend(UiTheme._target_blend(), true)


func _deck() -> void:
	app.modals.clear()
	GameSession.enter_boat_area(SessionState.AREA_EXTERIOR, &"start")
	app._show_current_boat_area()
	await _idle()
	var lighting := (app.router.current_screen as Node).get_node_or_null("Lighting")
	if lighting:
		lighting.update_now()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	Simulation.auto_advance = false
	WindField.get_default().test_override = func(_geo: Vector2, _time: float) -> WindField.Sample:
		return WindField.Sample.make(220.0, 8.0)
	app = APP_SCENE.instantiate()
	add_child(app)
	await _frames(12)
	app.start_new_game()
	await _idle()
	var looks := HarbourLooks.get_default()
	for port_id in HARBOURS:
		_moor_in(port_id, 12.5)
		await _deck()
		var look := "special" if looks.is_special(port_id) else String(looks.look_of(port_id))
		await _shot("deck_%s_%s" % [look, port_id])
	# The arrival card (English and Danish).
	_moor_in(&"valletta", 12.5)
	await _deck()
	app.toasts.clear()
	app._on_arrived(&"valletta")
	await _frames(20)
	await _shot("arrival_card_valletta", true)
	SettingsManager.set_language(&"da")
	_moor_in(&"zanzibar", 12.5)
	await _deck()
	app.toasts.clear()
	app._on_arrived(&"zanzibar")
	await _frames(20)
	await _shot("arrival_card_zanzibar_da", true)
	SettingsManager.set_language(&"en")
	# The special mark on the chart, by day and by night, with Valletta selected.
	for mood: Array in [["day", 12.5], ["night", 23.5]]:
		_moor_in(&"copenhagen", float(mood[1]))
		await _deck()
		app.open_chart_for_port(&"valletta")
		await _idle()
		await _frames(10)
		var chart := app.router.current_screen as WorldMap
		chart.get_map_view().frame_geo_points(PackedVector2Array([Vector2(12.0, 34.5), Vector2(17.5, 38.5)]))
		await _frames(10)
		await _shot("chart_special_valletta_%s" % mood[0])
		chart.get_map_view().frame_geo_points(PackedVector2Array([Vector2(26.0, 35.5), Vector2(29.5, 37.5)]))
		chart.select_port(&"symi")
		await _frames(10)
		await _shot("chart_special_symi_%s" % mood[0])
		app.close_chart()
		await _idle()
	# The Dreamer's Map: special stars beside the red visited pins.
	_moor_in(&"valletta", 12.5)
	await _deck()
	app.open_dream_map()
	await _idle()
	await _frames(10)
	var dream := app.router.current_screen as WorldMap
	dream.get_map_view().frame_geo_points(PackedVector2Array([Vector2(-12.0, 30.0), Vector2(30.0, 58.0)]))
	await _frames(10)
	await _shot("dream_map_specials")
	print("I021 SHOTS DONE")
	get_tree().quit()
