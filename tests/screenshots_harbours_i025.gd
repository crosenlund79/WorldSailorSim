extends Node
## I025, A Little More Room Aboard (Part II, items 13-14): rendered evidence
## of the harbour around the moored boat - the town's scale, architecture and
## colour per region and the neighbouring boats' scale - at chosen harbours.
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1600x900 res://tests/screenshots_harbours_i025.tscn -- --out=DIR \
##     [--ports=kiel,naples] [--vessel=ID] [--suffix=after]
## Uses the test save and settings files; never touches the player's own.

const APP_SCENE := preload("res://src/app/app.tscn")
const PORTS: Array[StringName] = [&"copenhagen", &"kiel", &"naples", &"dingle", &"dakar", &"bergen"]

var app: Node
var out := "res://docs/screenshots/i025/visual"
var ports: Array[StringName] = PORTS.duplicate()
var vessel := ""
var suffix := ""


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	SettingsManager.settings_path = "user://test_settings.cfg"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--vessel="):
			vessel = a.trim_prefix("--vessel=")
		elif a.begins_with("--suffix="):
			suffix = "_" + a.trim_prefix("--suffix=")
		elif a.begins_with("--ports="):
			ports.clear()
			for p in a.trim_prefix("--ports=").split(",", false):
				ports.append(StringName(p))
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
	var screen := app.router.current_screen as Node
	var lighting := screen.get_node_or_null("Lighting")
	if lighting:
		lighting._weather_at = -INF
		lighting.update_now()
	var sea := screen.get_node_or_null("SeaSurface") as SeaSurface
	if sea:
		sea._sample()
		for key: String in sea._target:
			sea.set(key, sea._target[key])


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
	if vessel != "":
		GameSession.test_all_boats_owned = true
		var refusal := GameSession.switch_vessel(StringName(vessel))
		if refusal != "":
			push_warning("screenshots_harbours_i025: %s" % refusal)
	for port_id in ports:
		_moor_in(port_id, 11.5)
		await _deck()
		app.toasts.clear()
		await get_tree().create_timer(0.6).timeout
		await _frames(4)
		await RenderingServer.frame_post_draw
		var v := ("_" + vessel) if vessel != "" else ""
		get_viewport().get_texture().get_image().save_png("%s/harbour_%s%s%s.png" % [out, port_id, v, suffix])
		print("SHOT %s" % port_id)
	print("I025 HARBOUR SHOTS DONE")
	get_tree().quit()
