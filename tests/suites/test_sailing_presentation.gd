extends RefCounted
## How wind and propulsion are presented in the real application: the sail
## rig and spinnaker on deck, the HUD, the chart's wind overlay and the engine
## sound. Propulsion states are forced through GameSession (as the simulation
## would set them) with the frame-driven clock switched off, so each scene
## shows a known state. Screenshots are saved when run with --screenshots.

const APP_SCENE := preload("res://src/app/app.tscn")

var t: Node
var app: Node


func run(runner: Node) -> void:
	t = runner
	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	app.start_new_game()
	await _settle()
	Simulation.auto_advance = false
	GameSession.plan_route_to(&"kiel")
	GameSession.depart()
	await _go_to(&"exterior")

	await _test_sails_by_wind_side()
	await _test_spinnaker()
	await _test_motoring_and_engine_audio()
	await _test_hud()
	await _test_chart_overlay()
	await _test_engine_stops()

	Simulation.auto_advance = true
	app.queue_free()
	await t.frames(2)
	GameSession.end_session()
	t.use_calm_wind()


## Forces a propulsion state, as the simulation would set it.
func _force(mode: StringName, twa: float, wind_kn := 14.0) -> void:
	var heading := Simulation.get_current_heading()
	var wind_from := fposmod(heading + twa, 360.0)
	t.set_wind(wind_from, wind_kn)
	var state := PropulsionController.evaluate(PropulsionState.new(), GameSession.get_vessel_profile(),
		GameSession.get_game_time(), heading, WindField.Sample.make(wind_from, wind_kn))
	state.mode = mode
	state.engine_reason = PropulsionState.REASON_POOR if mode == PropulsionState.MODE_ENGINE else PropulsionState.REASON_NONE
	state.spinnaker = mode == PropulsionState.MODE_SAIL and GameSession.get_vessel_profile().wants_spinnaker(twa)
	state.speed_kn = GameSession.get_vessel_profile().engine_speed_kn if mode == PropulsionState.MODE_ENGINE else state.potential_kn
	GameSession.set_propulsion(state)


func _rig() -> SailRig:
	var area := app.router.current_screen as BoatArea
	return area.get_node("SailRig") as SailRig if area and area.area_id == &"exterior" else null


func _test_sails_by_wind_side() -> void:
	_force(PropulsionState.MODE_SAIL, 60.0)
	await _go_to(&"interior")
	await _go_to(&"exterior")  # entering the deck snaps the rig to the state
	var rig := _rig()
	t.check(rig != null and not rig.is_furled(), "[sails] sails are set on deck while sailing")
	t.check_eq(rig.get_sail_side(), "port", "[sails] wind from starboard: the sails lie to port (leeward)")
	t.check(not rig.is_spinnaker_visible(), "[sails] no spinnaker on a close reach")
	var close_angle := absf(rig.main_angle_deg)
	await t.screenshot("19_deck_sailing_close_reach")

	_force(PropulsionState.MODE_SAIL, -100.0)
	await t.wait_until(func() -> bool: return rig.get_sail_side() == "starboard" and absf(rig.main_angle_deg) > close_angle + 10.0, 5.0)
	t.check_eq(rig.get_sail_side(), "starboard", "[sails] wind from port: the sails swing over to starboard")
	t.check(absf(rig.main_angle_deg) > close_angle + 10.0, "[sails] the main is eased further on a beam reach (%.0f° vs %.0f°)" % [absf(rig.main_angle_deg), close_angle])
	await t.screenshot("20_deck_sailing_beam_reach_port_wind")


func _test_spinnaker() -> void:
	_force(PropulsionState.MODE_SAIL, 150.0)
	t.check(GameSession.get_propulsion().spinnaker, "[spinnaker] the state sets the spinnaker at 150°")
	await _go_to(&"interior")
	await _go_to(&"exterior")
	var rig := _rig()
	t.check(rig.is_spinnaker_visible() and is_equal_approx(rig.spinnaker_amount, 1.0),
		"[spinnaker] it is flying as soon as the deck is entered (state-driven, not scene-driven)")
	t.check_eq(rig.get_sail_side(), "port", "[spinnaker] main to port with the wind on the starboard quarter")
	await t.screenshot("21_deck_spinnaker")
	_force(PropulsionState.MODE_SAIL, -165.0)
	await t.wait_until(func() -> bool: return rig.get_sail_side() == "starboard", 5.0)
	await t.frames(60)
	await t.screenshot("21b_deck_spinnaker_running")
	_force(PropulsionState.MODE_SAIL, 100.0)
	t.check(await t.wait_until(func() -> bool: return not rig.is_spinnaker_visible(), 5.0),
		"[spinnaker] it is taken down when the wind comes forward of 115°")


func _test_motoring_and_engine_audio() -> void:
	_force(PropulsionState.MODE_ENGINE, 20.0, 4.0)
	var rig := _rig()
	t.check(await t.wait_until(func() -> bool: return rig.is_furled(), 5.0), "[engine] the sails are furled while motoring")
	t.check(not rig.is_spinnaker_visible(), "[engine] no spinnaker while motoring")
	t.check(AudioManager.is_loop_playing(app.ENGINE_LOOP) and AudioManager.is_loop_playing(app.ENGINE_MUFFLED_LOOP),
		"[engine] the engine sound runs while motoring")
	t.check_eq(AudioManager.get_loop_target_db(app.ENGINE_LOOP), app.ENGINE_OUTSIDE_DB, "[engine] on deck the engine is loud (open air)")
	var player := AudioManager.get_loop_player(app.ENGINE_LOOP)
	t.check(player != null and player.bus == AudioManager.BUS_SFX, "[engine] the engine plays on the SFX bus (follows the SFX volume)")
	var stream := player.stream as AudioStreamWAV
	t.check(stream != null and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "[engine] the engine sample loops seamlessly")
	await t.screenshot("22_deck_motoring")

	# Going below: the same sound keeps running, only quieter and muffled.
	var restarted := [false]
	var watch := func() -> void:
		if not player.playing:
			restarted[0] = true
	t.get_tree().process_frame.connect(watch)
	await _go_to(&"interior")
	t.get_tree().process_frame.disconnect(watch)
	t.check(not restarted[0] and player.playing, "[engine] the engine does not stop or restart on a scene change")
	t.check_eq(AudioManager.get_loop_target_db(app.ENGINE_LOOP), AudioManager.SILENT_DB, "[engine] inside, the open-air layer fades out")
	t.check_eq(AudioManager.get_loop_target_db(app.ENGINE_MUFFLED_LOOP), app.ENGINE_INSIDE_DB, "[engine] inside, the muffled layer is heard, quieter")
	await t.screenshot("22b_cabin_motoring")


## I026: underway these readouts are the instruments' (InstrumentCluster; in
## words in the focused view), no longer the route panel's.
func _test_hud() -> void:
	var instruments: InstrumentCluster = app.hud.instrument_cluster
	instruments.refresh()
	var propulsion := instruments.get_value("propulsion")
	var wind := instruments.get_value("wind")
	t.check(propulsion.begins_with("Motoring") and "insufficient sailing performance" in propulsion,
		"[hud] shows motoring and why (%s)" % propulsion)
	t.check(" kn" in wind and ("port" in wind or "starboard" in wind or "off the bow" in wind),
		"[hud] shows the local wind and its angle (%s)" % wind)
	t.check("ETA about" in instruments.get_value("eta"), "[hud] shows a wind-aware ETA")
	_force(PropulsionState.MODE_SAIL, 135.0)
	instruments.refresh()
	propulsion = instruments.get_value("propulsion")
	t.check(propulsion.begins_with("Under sail · broad reach") and "spinnaker" in propulsion, "[hud] shows sailing and the spinnaker (%s)" % propulsion)
	await t.screenshot("22c_cabin_hud_sailing")


func _test_chart_overlay() -> void:
	WindField.get_default().test_override = Callable()  # the real wind field on the chart
	app.open_chart()
	await _settle()
	var map := app.router.current_screen as WorldMap
	if not t.check(map != null, "[chart] the chart opens"):
		return
	var view := map.get_map_view()
	view.reset_view()
	await t.frames(3)
	t.check(map.is_wind_shown() and view.wind_layer.visible and view.wind_layer.tint.visible, "[chart] the wind overlay is shown")
	t.check(map.find_child("WindLegend", true, false).visible, "[chart] the wind legend is shown")
	var start := Time.get_ticks_usec()
	view.wind_layer.update_time(GameSession.get_game_time(), true)
	await t.frames(2)
	print("    wind overlay first draw: %.1f ms" % ((Time.get_ticks_usec() - start) / 1000.0))
	await t.screenshot("23_chart_wind_europe")
	view.center_on_geo(Vector2(10.5, 55.0), 2.0)
	await t.frames(3)
	await t.screenshot("24_chart_wind_zoomed")
	# Panning reuses cached samples: redraws stay cheap.
	start = Time.get_ticks_usec()
	for i in 10:
		view.center_on_geo(Vector2(10.5 + i * 0.05, 55.0), 2.0)
		await t.frames(1)
	var per_frame := (Time.get_ticks_usec() - start) / 10000.0
	t.check(per_frame < 100.0, "[chart] panning with the wind overlay stays responsive (%.1f ms per frame)" % per_frame)
	map._on_cursor_moved(Vector2(5.0, 44.0))
	t.check(" kn" in (map.find_child("CursorLabel", true, false) as Label).text, "[chart] the cursor readout includes the wind there")
	await t.click(map.find_child("WindToggle", true, false))
	t.check(not map.is_wind_shown() and not view.wind_layer.visible and not map.find_child("WindLegend", true, false).visible,
		"[chart] the toggle hides the wind overlay and legend")
	await t.click(map.find_child("WindToggle", true, false))
	t.check(map.is_wind_shown(), "[chart] the toggle shows it again")
	t.check(AudioManager.is_loop_playing(app.ENGINE_MUFFLED_LOOP) == GameSession.is_motoring(), "[chart] the engine sound follows the state at the chart")
	app.close_chart()
	await _settle()


func _test_engine_stops() -> void:
	_force(PropulsionState.MODE_ENGINE, 0.0, 0.0)
	await t.frames(2)
	t.check(AudioManager.is_loop_playing(app.ENGINE_LOOP), "[engine] motoring again")
	_force(PropulsionState.MODE_SAIL, 120.0)
	t.check(not AudioManager.is_loop_playing(app.ENGINE_LOOP) and not AudioManager.is_loop_playing(app.ENGINE_MUFFLED_LOOP),
		"[engine] the engine fades out when the sails are set")
	_force(PropulsionState.MODE_ENGINE, 0.0, 0.0)
	GameSession.complete_voyage()
	t.check(not AudioManager.is_loop_playing(app.ENGINE_LOOP), "[engine] the engine stops on arrival")
	_force(PropulsionState.MODE_ENGINE, 0.0, 0.0)
	app.show_main_menu()
	await _settle()
	t.check(not AudioManager.is_loop_playing(app.ENGINE_LOOP) and not AudioManager.is_loop_playing(app.ENGINE_MUFFLED_LOOP),
		"[engine] no engine sound in the main menu")


func _go_to(area: StringName) -> void:
	app._on_area_change_requested(area, &"start" if area == &"exterior" else &"from_deck")
	await _settle()


func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)
