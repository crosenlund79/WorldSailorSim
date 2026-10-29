extends Node
## I027 Tier 4, the compact waterfront: rendered before/after evidence and
## the walking times. For each harbour: the whole quay in one picture (the
## camera zoomed out to its length), the walkway's head and the café at the
## game's own zoom, and - walking for real, the movement keys held at normal
## game speed - the seconds from the walkway's head to every business's
## door. Run it on the commit before the change for the "before".
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1600x900 res://tests/screenshots_i027_waterfront.tscn -- [--out=DIR] [--label=after]
## Prints "WATERFRONT {json}" (lengths, door distances, walking seconds).
## Uses the test save and settings files; never touches the player's own.

const APP_SCENE := preload("res://src/app/app.tscn")
const PORTS: Array[StringName] = [&"copenhagen", &"lohals", &"naples"]

var app: Node
var out := "res://docs/screenshots/i027/waterfront"
var label := "after"


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	SettingsManager.settings_path = "user://test_settings.cfg"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--label="):
			label = a.trim_prefix("--label=")
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
	while BusinessHours.local_weekday(port_id, state.game_time) != 3:
		state.game_time += 86400.0
	GameSession.replace_state(state)
	UiTheme.set_blend(UiTheme._target_blend(), true)


func _quay() -> HarbourFront:
	app.modals.clear()
	app.toasts.clear()
	if app.router.current_screen is HarbourFront:
		app.leave_quay()
		await _idle()
	GameSession.enter_boat_area(SessionState.AREA_EXTERIOR, &"from_boatyard")
	app._show_current_boat_area()
	await _idle()
	app.open_quay()
	await _idle()
	var front := app.router.current_screen as HarbourFront
	UiTheme.set_blend(UiTheme._target_blend(), true)
	return front


func _shot(name: String, settle := 0.5) -> void:
	await get_tree().create_timer(settle).timeout
	await _frames(3)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(out)
	get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out, label, name])
	print("SHOT %s_%s" % [label, name])


func _run() -> void:
	Simulation.auto_advance = false
	WindField.get_default().test_override = func(_g: Vector2, _t: float) -> WindField.Sample: return WindField.Sample.make(250.0, 8.0)
	app = APP_SCENE.instantiate()
	add_child(app)
	await _frames(12)
	app.start_new_game()
	await _idle()
	var report := {}
	for port in PORTS:
		_moor_in(port, 11.0)
		var front := await _quay()
		if front == null:
			continue
		var layout := front.layout
		var doors := {}
		for business in layout.get_businesses():
			doors[String(business)] = roundi(absf(layout.door_station(business).x - layout.arrival_point().x))
		var entry := {"length_m": snappedf((layout.right - layout.left) / 100.0, 0.1), "door_distance_cm": doors,
			"businesses": layout.get_businesses().size()}
		# The whole quay at once.
		front.player.position = layout.arrival_point()
		front.set_process(false)
		var view := get_viewport().get_visible_rect().size
		var zoom := view.x / (layout.right - layout.left + 200.0)
		front.camera.zoom = Vector2.ONE * zoom
		front.camera.position = Vector2((layout.left + layout.right) / 2.0, QuayLayout.EDGE_Y / 2.0)
		front.camera.reset_smoothing()
		await _shot("%s_overview" % port, 1.0)
		front.camera.zoom = Vector2.ONE * HarbourFront.ZOOM
		front.set_process(true)
		# The game's own zoom: the walkway's head, then the café.
		front.player.position = layout.arrival_point()
		front.camera.position.x = front._camera_x(front.player.position.x)
		front.camera.reset_smoothing()
		await _shot("%s_walkway" % port, 0.8)
		if port == &"copenhagen":
			entry["walk_seconds"] = await _walks(front)
		report[String(port)] = entry
	print("WATERFRONT ", JSON.stringify({"label": label, "build": GameVersion.build_label(true), "ports": report}))
	get_tree().quit()


## From the walkway's head to each door, holding the movement keys at normal
## game speed: real seconds, start to stop.
func _walks(front: HarbourFront) -> Dictionary:
	var seconds := {}
	for business in front.layout.get_businesses():
		front.player.position = front.layout.arrival_point()
		await get_tree().physics_frame
		var target := front.layout.door_station(business)
		var start := Time.get_ticks_msec()
		var guard := 0
		# Up to the walking lane (the "before" run, on the commit without one,
		# walked just below the doorsteps at y = 106), along it to the door,
		# then up until the door lights up.
		while absf(front.player.position.y - QuayLayout.LANE_Y) > 12.0 and guard < 2000:
			Input.action_press(&"move_up")
			await get_tree().physics_frame
			guard += 1
		Input.action_release(&"move_up")
		var action := &"move_left" if target.x < front.player.position.x else &"move_right"
		while absf(front.player.position.x - target.x) > 16.0 and guard < 6000:
			Input.action_press(action)
			await get_tree().physics_frame
			guard += 1
			if (action == &"move_left") != (target.x < front.player.position.x):
				break
		Input.action_release(action)
		while front.player.get_focused_interactable() != front.get_station(business) and front.player.position.y > target.y + 4.0 and guard < 7000:
			Input.action_press(&"move_up")
			await get_tree().physics_frame
			guard += 1
		Input.action_release(&"move_up")
		seconds[String(business)] = snappedf((Time.get_ticks_msec() - start) / 1000.0, 0.1)
		await _frames(2)
	return seconds
