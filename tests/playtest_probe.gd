extends Node
## A small rendered probe for checking a change by eye (I027 playtest fixes):
## starts a game moored in a harbour, shows a place, puts the Captain where
## asked, and saves screenshots. Also used to walk the Captain for real (the
## movement keys held) and report where it ended up.
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1600x900 res://tests/playtest_probe.tscn -- --out=DIR --scene=deck|cabin|quay \
##     [--port=copenhagen] [--hour=11] [--at=X,Y] [--walk=right:1.5,up:0.5] [--name=shot]
##     [--chart=lon,lat,px[;lon,lat,px...]] (Regions and Harbours 2026: opens the chart and
##     shoots each view, centred on lon,lat at px screen pixels per degree; "hover:id" or
##     "click:id" as a view hovers or clicks a named anchorage, "region:id" a region's mark)
## Prints "PROBE {json}". Uses the test save and settings files.

const APP_SCENE := preload("res://src/app/app.tscn")

var app: Node
var args := {"out": "user://probe", "scene": "deck", "port": "copenhagen", "hour": "11", "at": "", "walk": "", "name": "shot"}


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	SettingsManager.settings_path = "user://test_settings.cfg"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			args[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	_run.call_deferred()


func _idle() -> void:
	var guard := 0
	while app.router.is_busy() and guard < 2000:
		guard += 1
		await get_tree().process_frame
	for i in 6:
		await get_tree().process_frame


var _screens: Array[String] = []


func _note_screen() -> void:
	var screen: Node = app.router.current_screen
	var label := String(screen.get_script().get_global_name()) if screen and screen.get_script() else "?"
	var player: Node2D = screen.get("player") if screen else null
	if player:
		label += "@%d,%d" % [player.position.x, player.position.y]
	if _screens.is_empty() or not _screens.back().begins_with(label.get_slice("@", 0)):
		_screens.append(label)


func _shot(name: String) -> void:
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(args.out)
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [args.out, name])


func _chart_views() -> void:
	app.open_chart()
	await _idle()
	await get_tree().create_timer(0.6).timeout
	var map: WorldMap = app.router.current_screen
	var view: MapView = map.get_map_view()
	if args.get("wind", "1") == "0":
		map.set_wind_shown(false)
		view.show_weather = false
	var report := []
	var k := 0
	for part in String(args.chart).split(";", false):
		if part.begins_with("click:"):
			report.append({"click": part, "result": map.plan_via_anchorage(StringName(part.substr(6))), "draft": map.get_draft_anchorages()})
		elif part.begins_with("hover:") or part.begins_with("region:"):
			var id := StringName(part.get_slice(":", 1))
			view.hovered_anchorage = id if part.begins_with("hover:") else &""
			view.hovered_cruising_region = id if part.begins_with("region:") else &""
			map._update_cruising_tooltip()
			view._overlay.queue_redraw()
			report.append({"hover": part, "info": map.get_cruising_info_text()})
		else:
			var bits := part.split(",")
			view.center_on_geo(Vector2(float(bits[0]), float(bits[1])), float(bits[2]) / view.units_per_degree)
		await get_tree().create_timer(0.8).timeout
		await _shot("%s_%d" % [args.name, k])
		report.append({"view": k, "px": snappedf(view.get_px_per_degree(), 0.1), "anchorages": view.get_shown_anchorage_ids().size(),
			"ports": view.get_shown_port_ids().size(), "legend": map.is_cruising_legend_shown(), "status": map.get_course_status_text().left(300)})
		k += 1
	print("PROBE ", JSON.stringify(report))


func _run() -> void:
	OpeningStory.enabled = false
	AcademyGuide.enabled = false
	app = APP_SCENE.instantiate()
	add_child(app)
	app.router.fade_duration = 0.05
	await _idle()
	app.start_new_game()
	await _idle()
	var port := StringName(args.port)
	var state := GameSession.get_state_snapshot()
	state.location_id = port
	state.vessel_status = SessionState.STATUS_MOORED
	state.vessel_position = PortCatalog.get_default().get_port(port).get_geo_position()
	state.voyage = null
	if args.has("vessel"):
		state.vessel_id = StringName(args.vessel)
	var day_start := floorf(state.game_time / 86400.0) * 86400.0
	state.game_time = day_start + fposmod(float(args.hour) - state.vessel_position.x / 15.0, 24.0) * 3600.0
	GameSession.replace_state(state)
	match String(args.scene):
		"quay":
			GameSession.enter_boat_area(SessionState.AREA_EXTERIOR, &"from_boatyard")
			app._show_current_boat_area()
			await _idle()
			app.open_quay()
		"cabin":
			GameSession.enter_boat_area(SessionState.AREA_INTERIOR, &"start")
			app._show_current_boat_area()
		_:
			GameSession.enter_boat_area(SessionState.AREA_EXTERIOR, &"from_boatyard")
			app._show_current_boat_area()
	await _idle()
	if args.has("sail"):
		# Under way: a course to the harbour named and away (the deck stays shown).
		GameSession.plan_route_to(StringName(args.sail))
		GameSession.depart()
		await get_tree().create_timer(2.5).timeout
	UiTheme.set_blend(UiTheme._target_blend(), true)
	var screen: Node = app.router.current_screen
	var player: Node2D = screen.get("player")
	if player and not String(args.at).is_empty():
		var xy := String(args.at).split(",")
		player.position = Vector2(float(xy[0]), float(xy[1]))
	if args.has("open"):
		app.call(StringName(args.open))  # e.g. open_action_wheel
		await get_tree().create_timer(0.3).timeout
	if args.has("chart"):
		await _chart_views()
		get_tree().quit()
		return
	await _shot(String(args.name) + "_0")
	var report := {"scene": String(args.scene), "screen": screen.get_class() if screen.get_script() == null else String(screen.get_script().get_global_name()),
		"start": [player.position.x, player.position.y] if player else []}
	# Walk: "action:seconds" steps with the movement keys held.
	var step := 0
	for part in String(args.walk).split(",", false):
		var bits := part.split(":")
		var action := StringName("move_" + bits[0]) if not bits[0].begins_with("!") else StringName(bits[0].substr(1))
		if bits.size() > 2 and bits[2] == "run":
			Input.action_press(&"run")
		Input.action_press(action)
		var until := Time.get_ticks_msec() + int(float(bits[1]) * 1000.0)
		while Time.get_ticks_msec() < until:
			await get_tree().physics_frame
			_note_screen()
		Input.action_release(action)
		Input.action_release(&"run")
		await _idle()
		step += 1
		screen = app.router.current_screen
		player = screen.get("player")
		await _shot("%s_%d" % [args.name, step])
	# Goto: "place[,place]" - the quay's action wheel's walk, then what opened.
	if args.has("goto"):
		var opened := []
		for place in String(args.goto).split(",", false):
			app.modals.clear()
			await get_tree().process_frame
			var ok: bool = screen.walk_to_place(StringName(place))
			var until := Time.get_ticks_msec() + 9000
			while Time.get_ticks_msec() < until and screen.walking_to != &"":
				await get_tree().physics_frame
			await get_tree().create_timer(0.3).timeout
			var top: Node = app.modals.get_top()
			opened.append("%s:%s:%s@%d,%d" % [place, ok, top.get_script().get_global_name() if top and top.get_script() else "-",
				player.position.x, player.position.y])
			await _shot("%s_goto_%s" % [args.name, place])
		report["goto"] = opened
	report["end_screen"] = String(screen.get_script().get_global_name()) if screen and screen.get_script() else ""
	report["end"] = [player.position.x, player.position.y] if player else []
	report["modals"] = app.modals.depth()
	report["kn"] = snappedf(GameSession.get_vessel_speed_kn(), 0.1)
	if player and player.has_method(&"get_focused_interactable"):
		var focus: Interactable = player.get_focused_interactable()
		report["focused"] = String(focus.interaction_id) if focus else ""
	report["screens"] = _screens
	if args.has("stations"):
		var list := {}
		for node in screen.find_children("*", "Interactable", true, false):
			var station := node as Interactable
			if station.is_visible_in_tree() and station.enabled:
				list[String(station.interaction_id)] = [roundi(station.global_position.x), roundi(station.global_position.y)]
		report["stations"] = list
	if screen and screen.has_method(&"get_walkway_return_point"):
		var back: Vector2 = screen.get_walkway_return_point()
		report["walkway_return"] = [back.x, back.y]
	print("PROBE ", JSON.stringify(report))
	get_tree().quit()
