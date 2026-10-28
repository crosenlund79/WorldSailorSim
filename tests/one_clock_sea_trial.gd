extends Node
## Operation One Clock: where the frame time goes when game time runs faster
## than 1x, especially through dawn and dusk. A diagnostic sea trial, never
## part of normal play: it runs only when this scene is started on purpose,
## on scratch saves and settings (the player's own are never touched).
##
## For the Captain (Windows): open the project in Godot, open
## tests/one_clock_sea_trial.tscn, press F6 (Run Current Scene) and wait about
## five minutes without touching anything. The results appear on screen, are
## copied to the clipboard and saved in one_clock_sea_trial.txt (the path is
## shown); paste or send that text.
##
## Each frame it times, separately, the systems that follow the clock: the
## simulation step (Simulation.tick), the interface recolouring
## (UiTheme._process -> set_blend), the boat's light (BoatLighting._process)
## and the dawn/dusk watch (DayNightWatch._process). It does so by switching
## their own processing off and calling the same function itself, once per
## frame, exactly as the engine would. Everything else (rendering, other
## scripts) is the rest of the frame.
##
## Developers (all scenarios, Linux):
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1600x900 res://tests/one_clock_sea_trial.tscn -- --all --out=/tmp/one_clock.json [--only=a,b]
const APP_SCENE := preload("res://src/app/app.tscn")

var app: Node
var results := {}
var _frames_log: Array = []
var _recording := false
var _last_usec := 0
var _palette_changes := 0
var _theme_changed := 0
## Diagnostic switches (isolation runs only).
var freeze_theme := false
var freeze_lighting := false
var _status: Label
var _lines: Array[String] = []
var _gpu_ms: Array[float] = []
var _cpu_render_ms: Array[float] = []
var dialogs := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.save_dir = "user://test_saves"
	SettingsManager.settings_path = "user://test_settings.cfg"
	_run.call_deferred()


func _arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.get_slice("=", 1)
	return fallback


## The short sea trial (the default): the states and speeds that matter.
const TRIAL := ["sail_day_1x", "sail_day_20x", "sail_night_1x", "sail_night_20x", "dusk_20x_cards", "dusk_20x_nocards",
	"chart_dusk_20x_nocards", "harbour_night_1x", "harbour_night_20x", "harbour_night_lights_off", "long"]


func _wanted(label: String) -> bool:
	var only := _arg("only", "")
	if only != "":
		return label in only.split(",")
	return OS.get_cmdline_user_args().has("--all") or label in TRIAL


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


# --- Per-frame timing --------------------------------------------------------------------------

func _timed(node: Node, call: Callable) -> float:
	if node == null or not is_instance_valid(node) or not node.can_process():
		return 0.0
	var t := Time.get_ticks_usec()
	call.call()
	return (Time.get_ticks_usec() - t) / 1000.0


func _lighting() -> Node:
	var area := app.router.current_screen as BoatArea if app else null
	var lighting := area.get_node_or_null(^"Lighting") if area else null
	if lighting and lighting.is_processing():
		lighting.set_process(false)
	return lighting


func _process(_delta: float) -> void:
	if app == null:
		return
	var now := Time.get_ticks_usec()
	var dt := (now - _last_usec) / 1e6 if _last_usec > 0 else 1.0 / 60.0
	_last_usec = now
	var game_before := GameSession.get_game_time()
	var blend_before: float = UiTheme.blend
	var palette_before := _palette_changes
	var sim_ms := _timed(Simulation, func() -> void: Simulation.tick(dt))
	var watch_ms := _timed(app.day_night_watch, func() -> void: app.day_night_watch._process(dt))
	var theme_ms := 0.0 if freeze_theme else _timed(UiTheme, func() -> void: UiTheme._process(dt))
	var lighting := _lighting()
	var light_ms := 0.0 if freeze_lighting else _timed(lighting, func() -> void: lighting._process(dt))
	if not _recording:
		return
	var game_after := GameSession.get_game_time()
	var vp := get_viewport().get_viewport_rid()
	_frames_log.append({
		"gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(vp),
		"render_cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(vp),
		"frame_ms": dt * 1000.0,
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"sim_ms": sim_ms, "theme_ms": theme_ms, "light_ms": light_ms, "watch_ms": watch_ms,
		"game_s": game_after - game_before,
		"evals": int(floor(game_after / Simulation.EVALUATION_INTERVAL)) - int(floor(game_before / Simulation.EVALUATION_INTERVAL)),
		"blend_step": not is_equal_approx(blend_before, UiTheme.blend),
		"palette": _palette_changes - palette_before,
		"card": app.get("time_passage") != null and is_instance_valid(app.get("time_passage")),
		"paused": get_tree().paused,
		"elev": Daylight.sun_elevation(GameSession.get_vessel_position(), game_after),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"lights": lighting.find_children("*", "PointLight2D", true, false).filter(func(l: PointLight2D) -> bool: return l.is_visible_in_tree()).size() if lighting else -1,
		"dark": float(lighting.get("_darkness")) if lighting else -1.0,
		"scale": GameSession.get_time_scale(),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
	})


func _pct(sorted: Array, q: float) -> float:
	return sorted[mini(int(sorted.size() * q), sorted.size() - 1)]


## Records `seconds` of real time (with `per_frame` called each frame), then
## summarises the frames.
func _record(label: String, seconds: float, per_frame := Callable()) -> Dictionary:
	_frames_log.clear()
	_recording = true
	var start := Time.get_ticks_msec()
	var game_start := GameSession.get_game_time()
	var i := 0
	while Time.get_ticks_msec() - start < seconds * 1000.0:
		if per_frame.is_valid():
			per_frame.call(i)
		await get_tree().process_frame
		i += 1
	_recording = false
	return _summarise(label, GameSession.get_game_time() - game_start)


func _summarise(label: String, game_seconds: float) -> Dictionary:
	var frames: Array = _frames_log.duplicate()
	if frames.size() < 3:
		return {}
	frames.pop_front()  # the first frame's time includes the setup before recording
	var frame_ms: Array = frames.map(func(f: Dictionary) -> float: return f.frame_ms)
	var sorted := frame_ms.duplicate()
	sorted.sort()
	var sum := func(key: String) -> float:
		var total := 0.0
		for f in frames:
			total += float(f[key])
		return total
	var worst := frames[frame_ms.find(sorted[-1])] as Dictionary
	var n := float(frames.size())
	var entry := {
		"frames": frames.size(),
		"mean_ms": snappedf(sum.call("frame_ms") / n, 0.01), "median_ms": snappedf(_pct(sorted, 0.5), 0.01),
		"p95_ms": snappedf(_pct(sorted, 0.95), 0.01), "p99_ms": snappedf(_pct(sorted, 0.99), 0.01),
		"worst_ms": snappedf(sorted[-1], 0.01),
		"over_50ms": sorted.filter(func(x: float) -> bool: return x > 50.0).size(),
		"over_100ms": sorted.filter(func(x: float) -> bool: return x > 100.0).size(),
		"process_ms_mean": snappedf(sum.call("process_ms") / n, 0.01),
		"sim_ms_mean": snappedf(sum.call("sim_ms") / n, 0.001),
		"sim_ms_max": snappedf(frames.map(func(f: Dictionary) -> float: return f.sim_ms).max(), 0.01),
		"gpu_ms_mean": snappedf(sum.call("gpu_ms") / n, 0.01),
		"gpu_ms_max": snappedf(frames.map(func(f: Dictionary) -> float: return f.gpu_ms).max(), 0.01),
		"render_cpu_ms_mean": snappedf(sum.call("render_cpu_ms") / n, 0.01),
		"theme_ms_total": snappedf(sum.call("theme_ms"), 0.1),
		"theme_ms_max": snappedf(frames.map(func(f: Dictionary) -> float: return f.theme_ms).max(), 0.01),
		"blend_steps": frames.filter(func(f: Dictionary) -> bool: return f.blend_step).size(),
		"palette_changes": int(sum.call("palette")),
		"light_ms_mean": snappedf(sum.call("light_ms") / n, 0.001),
		"light_ms_max": snappedf(frames.map(func(f: Dictionary) -> float: return f.light_ms).max(), 0.01),
		"watch_ms_max": snappedf(frames.map(func(f: Dictionary) -> float: return f.watch_ms).max(), 0.01),
		"evals_total": int(sum.call("evals")),
		"evals_max_per_frame": int(frames.map(func(f: Dictionary) -> int: return f.evals).max()),
		"card_frames": frames.filter(func(f: Dictionary) -> bool: return f.card).size(),
		"paused_frames": frames.filter(func(f: Dictionary) -> bool: return f.paused).size(),
		"game_minutes": snappedf(game_seconds / 60.0, 0.1),
		"elev_from_to": [snappedf(float(frames[0].elev), 0.1), snappedf(float(frames[-1].elev), 0.1)],
		"nodes_from_to": [frames[0].nodes, frames[-1].nodes],
		"worst_frame": {"sim_ms": snappedf(worst.sim_ms, 0.01), "theme_ms": snappedf(worst.theme_ms, 0.01),
			"light_ms": snappedf(worst.light_ms, 0.01), "watch_ms": snappedf(worst.watch_ms, 0.01),
			"process_ms": snappedf(worst.process_ms, 0.01), "card": worst.card, "blend_step": worst.blend_step,
			"elev": snappedf(float(worst.elev), 0.1)},
	}
	entry["per_frame"] = frames.map(func(f: Dictionary) -> Array: return [snappedf(f.frame_ms, 0.1), snappedf(float(f.elev), 0.01),
		f.lights, snappedf(float(f.dark), 0.001), f.scale, f.draw_calls, f.objects, snappedf(f.process_ms, 0.01), f.card])
	results[label] = entry
	_lines.append("%-26s %6.1f %6.1f %6.1f %7.1f %5d %6.2f %6.1f %6.1f %5.2f %6.2f" % [label, entry.median_ms, entry.p95_ms, entry.p99_ms,
		entry.worst_ms, entry.over_50ms, entry.sim_ms_mean, entry.theme_ms_total, entry.theme_ms_max, entry.light_ms_mean, entry.gpu_ms_mean])
	if _status:
		_status.text = "One Clock sea trial: %s done (%d)" % [label, _lines.size()]
	print("%-34s med %6.1f p95 %6.1f p99 %6.1f worst %6.1f ms | >50 %3d | sim %5.2f/%6.2f theme %6.1f/%5.1f (%d steps) light %4.2f evals %d card %d | %.0f game-min elev %s" % [
		label, entry.median_ms, entry.p95_ms, entry.p99_ms, entry.worst_ms, entry.over_50ms, entry.sim_ms_mean, entry.sim_ms_max,
		entry.theme_ms_total, entry.theme_ms_max, entry.blend_steps, entry.light_ms_mean, entry.evals_total, entry.card_frames,
		entry.game_minutes, entry.elev_from_to])
	return entry


# --- Setting the scene -------------------------------------------------------------------------

func _set_time(t: float) -> void:
	var state := GameSession.get_state_snapshot()
	state.game_time = t
	GameSession.replace_state(state)
	app.snap_light()


## Underway in the Kattegat, on a route north (Copenhagen to Gothenburg).
func _underway(to: StringName = &"bergen") -> void:
	_moor(&"copenhagen")
	GameSession.plan_route_to(to)
	GameSession.depart()
	Simulation.advance(3.0 * 3600.0)  # out into open water
	await _show(SessionState.AREA_EXTERIOR)


func _moor(port: StringName) -> void:
	var state := GameSession.get_state_snapshot()
	state.location_id = port
	state.vessel_status = SessionState.STATUS_MOORED
	state.vessel_position = PortCatalog.get_default().get_port(port).get_geo_position()
	state.voyage = null
	state.planned_route = null
	GameSession.replace_state(state)


func _show(area: StringName) -> void:
	if app.router.current_screen is WorldMap:
		app.close_chart()
	app.modals.clear()
	GameSession.enter_boat_area(area, &"start")
	app._show_current_boat_area()
	await _frames(20)
	app.toasts.clear()


## The game time `minutes` before the sun next crosses `elevation`.
static func _before_crossing(geo: Vector2, from: float, elevation: float, rising: bool, minutes: float) -> float:
	var t := from
	var before := Daylight.sun_elevation(geo, t)
	for i in 3 * 24 * 60:
		t += 60.0
		var now := Daylight.sun_elevation(geo, t)
		if (rising and before < elevation and now >= elevation) or (not rising and before > elevation and now <= elevation):
			return t - minutes * 60.0
		before = now
	return from


func _twilight_minutes(evening: bool) -> float:
	var geo := GameSession.get_vessel_position()
	var start := _before_crossing(geo, GameSession.get_game_time(), DayNightWatch.DAY_ABOVE if evening else DayNightWatch.NIGHT_BELOW,
		not evening, 0.0)
	var t := start
	while t - start < 6 * 3600.0:
		t += 60.0
		var e := Daylight.sun_elevation(geo, t)
		if (evening and e <= DayNightWatch.NIGHT_BELOW) or (not evening and e >= DayNightWatch.DAY_ABOVE):
			break
	return (t - start) / 60.0


func _speed(scale: int) -> void:
	if GameSession.is_paused():
		GameSession.set_paused(false)
	GameSession.set_time_scale(scale)


## Waits until no card shows and the game is unpaused (between scenarios).
func _settle() -> void:
	app.modals.clear()
	var guard := 0
	while (app.get("time_passage") != null and is_instance_valid(app.get("time_passage")) or get_tree().paused) and guard < 1200:
		await get_tree().process_frame
		guard += 1
	GameSession.set_time_scale(1)
	await _frames(5)


# --- The scenarios -----------------------------------------------------------------------------

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var overlay := CanvasLayer.new()
	overlay.layer = 200
	add_child(overlay)
	_status = Label.new()
	_status.position = Vector2(24, 980)
	_status.add_theme_font_size_override(&"font_size", 22)
	_status.add_theme_color_override(&"font_color", Color.YELLOW)
	_status.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_status.add_theme_constant_override(&"outline_size", 6)
	_status.text = "One Clock sea trial: starting (about five minutes; please do not touch anything)"
	overlay.add_child(_status)
	WindField.get_default().test_override = func(_geo: Vector2, _time: float) -> WindField.Sample:
		return WindField.Sample.make(200.0, 11.0)
	app = APP_SCENE.instantiate()
	add_child(app)
	await _frames(5)
	while app.has_method("is_loading") and app.is_loading():
		await get_tree().process_frame
	app.start_new_game()
	await _frames(30)
	Simulation.set_process(false)
	UiTheme.set_process(false)
	app.day_night_watch.set_process(false)
	UiTheme.palette_changed.connect(func() -> void: _palette_changes += 1)
	var state := GameSession.get_state_snapshot()
	state.vessel_id = &"starling_33"
	GameSession.replace_state(state)
	results["renderer"] = RenderingServer.get_video_adapter_name() + " / " + RenderingServer.get_video_adapter_vendor()
	results["display"] = DisplayServer.get_name()
	print("ONE CLOCK sea trial on %s (%s)" % [results.renderer, results.display])
	await _underway()
	var t0 := GameSession.get_game_time()
	results["twilight_minutes_kattegat_may"] = {"dusk": _twilight_minutes(true), "dawn": _twilight_minutes(false)}
	print("Kattegat twilight now: dusk %.0f min, dawn %.0f min (cards only up to %.0f)" % [_twilight_minutes(true),
		_twilight_minutes(false), DayNightWatch.MAX_SKIP_SECONDS / 60.0])
	var geo := GameSession.get_vessel_position()

	# 1. Day and night sailing, steady (no transition), at each speed.
	for mood in ["day", "night"]:
		for scale in SessionState.TIME_SCALES:
			var label := "sail_%s_%dx" % [mood, scale]
			if not _wanted(label) and not _wanted("steady"):
				continue
			await _underway()
			if mood == "day":
				_set_time(_before_crossing(geo, GameSession.get_game_time(), 40.0, true, 0.0))
			else:
				_set_time(_before_crossing(geo, GameSession.get_game_time(), -10.0, false, -30.0))
			await _frames(30)
			_speed(scale)
			await _record(label, 12.0)
			GameSession.set_time_scale(1)
			await _settle()

	# 2. Through dusk and dawn underway, at each speed, with and without the cards.
	for cards in [true, false]:
		TimePassage.enabled = cards
		for evening in [true, false]:
			for scale in SessionState.TIME_SCALES:
				var label := "%s_%dx_%s" % ["dusk" if evening else "dawn", scale, "cards" if cards else "nocards"]
				if not _wanted(label) and not _wanted("twilight"):
					continue
				await _underway()
				var lead := 10.0 * scale  # game minutes before the twilight starts (10 real s)
				_set_time(_before_crossing(geo, GameSession.get_game_time(), DayNightWatch.DAY_ABOVE if evening else DayNightWatch.NIGHT_BELOW,
					not evening, lead))
				await _frames(20)
				_speed(scale)
				await _record(label, 25.0 if scale > 1 else 30.0)
				GameSession.set_time_scale(1)
				await _settle()

	# 3. The chart open through dusk (cards off and on), and in harbour.
	for cards in [false, true]:
		TimePassage.enabled = cards
		for scale in [5, 20]:
			var label := "chart_dusk_%dx_%s" % [scale, "cards" if cards else "nocards"]
			if not _wanted(label) and not _wanted("chart"):
				continue
			await _underway()
			_set_time(_before_crossing(geo, GameSession.get_game_time(), DayNightWatch.DAY_ABOVE, false, 5.0 * scale))
			app.open_chart()
			await _frames(30)
			_speed(scale)
			await _record(label, 25.0)
			GameSession.set_time_scale(1)
			await _settle()
			await _show(SessionState.AREA_EXTERIOR)
	TimePassage.enabled = true

	# 4. Isolation through dusk at 20x without cards: what each system costs.
	TimePassage.enabled = false
	for spec in [["iso_normal", false, false], ["iso_theme_frozen", true, false], ["iso_light_frozen", false, true],
			["iso_both_frozen", true, true]]:
		if not _wanted(spec[0]) and not _wanted("iso"):
			continue
		freeze_theme = spec[1]
		freeze_lighting = spec[2]
		await _underway()
		_set_time(_before_crossing(geo, GameSession.get_game_time(), DayNightWatch.DAY_ABOVE, false, 60.0))
		await _frames(20)
		_speed(20)
		await _record(spec[0], 25.0)
		GameSession.set_time_scale(1)
		freeze_theme = false
		freeze_lighting = false
		await _settle()
	TimePassage.enabled = true

	# 5. Rapid speed changes around dusk (cards on, as the Captain plays).
	if _wanted("rapid"):
		await _underway()
		_set_time(_before_crossing(geo, GameSession.get_game_time(), DayNightWatch.DAY_ABOVE, false, 60.0))
		await _frames(20)
		await _record("rapid_speed_changes", 25.0, func(i: int) -> void:
			if i % 15 == 0 and not get_tree().paused:
				_speed(SessionState.TIME_SCALES[(i / 15) % SessionState.TIME_SCALES.size()]))
		GameSession.set_time_scale(1)
		await _settle()

	# 6. In harbour (moored, Copenhagen) through dusk at 20x, cards on.
	if _wanted("harbour"):
		_moor(&"copenhagen")
		await _show(SessionState.AREA_EXTERIOR)
		var cph := GameSession.get_vessel_position()
		_set_time(_before_crossing(cph, GameSession.get_game_time(), DayNightWatch.DAY_ABOVE, false, 100.0))
		await _frames(20)
		_speed(20)
		await _record("harbour_dusk_20x_cards", 25.0)
		GameSession.set_time_scale(1)
		await _settle()
		await _underway()

	# 6b. In harbour at night, steady (no transition), 1x and 20x.
	for scale in [1, 20]:
		var label := "harbour_night_%dx" % scale
		if not _wanted(label) and not _wanted("harbour"):
			continue
		_moor(&"copenhagen")
		await _show(SessionState.AREA_EXTERIOR)
		var cph2 := GameSession.get_vessel_position()
		_set_time(_before_crossing(cph2, GameSession.get_game_time(), -10.0, false, -20.0))
		await _frames(20)
		_speed(scale)
		await _record(label, 12.0)
		GameSession.set_time_scale(1)
		await _settle()

	# 6c. In harbour at night with the boat's and quay's lights hidden (what the lights cost).
	if _wanted("harbour_night_lights_off"):
		_moor(&"copenhagen")
		await _show(SessionState.AREA_EXTERIOR)
		var cph3 := GameSession.get_vessel_position()
		_set_time(_before_crossing(cph3, GameSession.get_game_time(), -10.0, false, -20.0))
		await _frames(20)
		freeze_lighting = true
		var lights: Array[Node] = app.router.current_screen.find_children("*", "PointLight2D", true, false)
		for l in lights:
			l.visible = false
		await _record("harbour_night_lights_off", 12.0)
		freeze_lighting = false
		await _settle()

	# 7. A long run at 20x underway (cards on): several days and nights.
	if _wanted("long"):
		await _underway(&"bergen")
		var seconds := float(_arg("long_seconds", "60" if not OS.get_cmdline_user_args().has("--all") else "150"))
		dialogs = 0
		_speed(20)
		await _record("long_20x_cards", seconds, func(_i: int) -> void:
			var card_up: bool = app.get("time_passage") != null and is_instance_valid(app.get("time_passage"))
			if not card_up and not app.modals.is_empty():
				dialogs += 1
				app.modals.clear()  # a notice or dialog: the captain reads it and carries on
			if GameSession.get_time_scale() != 20 and not get_tree().paused and GameSession.is_underway():
				_speed(20))  # an event brought it back to 1x: carry on, as a captain at the helm would
		results["long_20x_cards"]["dialogs_dismissed"] = dialogs
		print("  dialogs dismissed during the long run: %d" % dialogs)
		GameSession.set_time_scale(1)
		await _settle()

	var out := _arg("out", "")
	if out != "":
		var file := FileAccess.open(out, FileAccess.WRITE)
		file.store_string(JSON.stringify(results, "  "))
	var summary := _summary_text()
	var path := "user://one_clock_sea_trial.txt"
	var text_file := FileAccess.open(path, FileAccess.WRITE)
	if text_file:
		text_file.store_string(summary)
		text_file.close()
	DisplayServer.clipboard_set(summary)
	print(summary)
	print("ONE CLOCK DONE")
	if DisplayServer.get_name() == "headless" or out != "":
		get_tree().quit()
		return
	# On screen until the window is closed.
	app.queue_free()
	var panel := ColorRect.new()
	panel.color = Color(0.04, 0.08, 0.11, 0.97)
	panel.size = Vector2(1920, 1080)
	overlay.add_child(panel)
	var label := Label.new()
	label.position = Vector2(40, 30)
	label.add_theme_font_size_override(&"font_size", 17)
	label.add_theme_color_override(&"font_color", Color(0.95, 0.9, 0.8))
	label.text = summary + "\nCopied to the clipboard and saved as %s\nClose the window when done." % ProjectSettings.globalize_path(path)
	overlay.add_child(label)
	_status.queue_free()


func _summary_text() -> String:
	var head := "LITTLE CAPTAIN'S HAT - ONE CLOCK SEA TRIAL\n%s | %s | %s | %s\nversion %s, %s\n" % [
		OS.get_name(), results.get("renderer", "?"), RenderingServer.get_current_rendering_method(),
		DisplayServer.screen_get_size(), GameVersion.describe(), Time.get_datetime_string_from_system()]
	var table := "\n%-26s %6s %6s %6s %7s %5s %6s %6s %6s %5s %6s\n" % ["scenario (frame ms)", "median", "p95", "p99", "worst",
		">50ms", "sim", "theme", "step", "light", "gpu"]
	return head + table + "\n".join(_lines) + "\n"
