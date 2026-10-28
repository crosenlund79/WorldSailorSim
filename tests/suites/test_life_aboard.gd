extends RefCounted
## Iteration 003b through the real application: chart panel stability, the
## sleep dialog (arrows, limits, from the cabin and the chart, waking at the
## V-berth), the ship's cat or dog, the helm's sail check, sail motion and the
## spinnaker's geometry. Screenshots are saved with --screenshots.

const APP_SCENE := preload("res://src/app/app.tscn")
const WAKE_MARKER := Vector2(282, 0)

var t: Node
var app: Node


func run(runner: Node) -> void:
	t = runner
	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	Simulation.auto_advance = false

	await _test_new_game_companion_choice()
	await _test_companion_spots_and_schedule()
	await _test_petting(CompanionState.KIND_CAT)
	await _test_sleep_dialog()
	await _test_sleep_from_cabin()
	await _test_chart_panel_stability()
	await _test_sleep_from_chart()
	await _test_interrupted_sleep()
	await _test_helm_and_sails()
	await _test_companion_persistence()
	await _test_dog_game()

	Simulation.auto_advance = true
	app.queue_free()
	await t.frames(2)
	GameSession.end_session()
	t.use_calm_wind()


# --- Companion -------------------------------------------------------------------------

func _test_new_game_companion_choice() -> void:
	t.check(app.router.current_screen is MainMenu, "(setup) on the main menu")
	await t.click(_button(app.router.current_screen, "NewGameButton"))
	var menu := app.modals.get_top() as NewGameMenu
	if not t.check(menu != null, "[companion] New Game offers the cat/dog choice"):
		return
	t.check_eq(menu.companion_kind, CompanionState.KIND_CAT, "[companion] the cat is preselected")
	await t.click(_button(menu, "DogButton"))
	t.check(menu.companion_kind == CompanionState.KIND_DOG and (_button(menu, "DogButton")).button_pressed
		and not _button(menu, "CatButton").button_pressed, "[companion] choosing the dog")
	await t.screenshot("25_new_game_companion")
	await t.click(_button(menu, "CatButton"))
	await t.click(_button(menu, "StartButton"))
	await _settle()
	t.check(app.router.current_screen is BoatArea and GameSession.get_companion().kind == CompanionState.KIND_CAT,
		"[companion] the game starts with the chosen cat")
	t.check_eq(GameSession.get_vessel_id(), &"arctic_wanderer_26", "[companion] aboard the Arctic Wanderer 26")
	# The walks in this suite were written for the Wing 33's cabin (the starter until 0.100b).
	await t.board(&"starling_33", app)
	var companion := _companion()
	t.check(companion != null and companion.visible and companion.kind == CompanionState.KIND_CAT, "[companion] the cat rests in the cabin")
	t.check_eq(_companion_count(), 1, "[companion] exactly one companion")
	if companion:
		t.check(companion.position.is_equal_approx(companion.get_spot_position(GameSession.get_companion().spot)), "[companion] at its saved resting spot")


func _test_companion_spots_and_schedule() -> void:
	var area := app.router.current_screen as BoatArea
	var standing := {
		"chart table": [Vector2(-232, 62), &"nav_table"],
		"berth": [Vector2(276, 0), &"bed"],
		"wake-up spot": [WAKE_MARKER, &"bed"],
		"companionway": [Vector2(-222, 8), &"companionway"],
	}
	for kind in CompanionState.KINDS:
		for spot in CompanionState.get_spot_ids(kind):
			var at: Vector2 = _companion().get_spot_position(spot)
			t.check(area.walkable_bounds.has_point(at), "[companion] %s spot '%s' is inside the cabin" % [kind, spot])
			_set_companion(kind, spot)
			await t.physics_frames(2)
			var blocked := []
			for place: String in standing:
				await _move_player_to(standing[place][0])
				var focused := area.player.get_focused_interactable()
				if focused == null or focused.interaction_id != standing[place][1]:
					blocked.append(place)
			t.check(blocked.is_empty(), "[companion] %s at '%s' never takes over the %s" % [kind, spot,
				", ".join(blocked) if blocked else "chart table, berth or companionway"])
	_set_companion(CompanionState.KIND_CAT, &"settee")

	# The schedule: occasional, deterministic, independent of step size.
	var start := SessionState.get_start_time()
	var one := CompanionState.create(CompanionState.KIND_CAT, start)
	one.advance_to(start + 48.0 * 3600.0)
	var stepped := CompanionState.create(CompanionState.KIND_CAT, start)
	var spots_seen := {}
	var changes := 0
	var last_change := start
	var shortest := INF
	for minute in range(1, 48 * 60 + 1):
		var time := start + minute * 60.0
		if stepped.advance_to(time):
			changes += 1
			shortest = minf(shortest, time - last_change)
			last_change = time
			spots_seen[stepped.spot] = true
	t.check(stepped.spot == one.spot and stepped.moves == one.moves and stepped.next_move_time == one.next_move_time,
		"[companion] the resting schedule is the same in one 48 h step and in minutes")
	t.check(changes >= 8 and changes <= 24 and shortest >= CompanionState.MIN_REST_SECONDS - 60.0,
		"[companion] it changes spot only occasionally (%d times in 48 h, at least %s apart)" % [changes, Simulation.format_duration(shortest)])
	t.check(spots_seen.size() == CompanionState.get_spot_ids(CompanionState.KIND_CAT).size(), "[companion] it uses all its resting spots")

	# Time passing in the game moves it (instantly), still exactly one companion.
	var before := GameSession.get_companion()
	Simulation.advance(before.next_move_time - GameSession.get_game_time() + 1.0)
	await t.frames(1)
	# I024: in view it walks there (no pop); out of view it is simply there.
	await t.wait_until(func() -> bool: return not _companion().is_walking(), 20.0)
	t.check(GameSession.get_companion().spot != before.spot and _companion().spot == GameSession.get_companion().spot
		and _companion().position.is_equal_approx(_companion().get_spot_position(GameSession.get_companion().spot)),
		"[companion] when its time comes it walks over and is found resting somewhere else")
	_set_companion(CompanionState.KIND_CAT, &"settee")


func _test_petting(kind: StringName) -> void:
	var area := app.router.current_screen as BoatArea
	var companion := _companion()
	var name := CompanionState.display_name(kind)
	await _move_player_to(_free_spot_near(companion.position))
	var focused := area.player.get_focused_interactable()
	t.check(focused != null and focused.interaction_id == &"pet", "[companion] the %s can be reached on foot" % name)
	t.check_eq(app.hud.get_prompt(), "Pet the %s" % name, "[companion] approaching shows 'Pet the %s' (I024 wording; a named one: 'Pet <name>')" % name)
	var petted := [false]
	var on_petted := func(_kind: StringName) -> void: petted[0] = true
	companion.petted.connect(on_petted)
	await t.press_action(&"interact")
	companion.petted.disconnect(on_petted)
	t.check(petted[0] and companion.is_reacting(), "[companion] E pets the %s and it reacts" % name)
	var player := _sfx_player_with(companion.get_sound())
	t.check(player != null, "[companion] the %s's sound plays (%s)" % [name, companion.get_sound().resource_path.get_file()])
	t.check(player != null and player.bus == AudioManager.BUS_SFX, "[companion] on the SFX bus (follows the SFX and Master volume)")
	var sfx := AudioServer.get_bus_index(AudioManager.BUS_SFX)
	var volume := SettingsManager.get_volume(&"SFX")
	SettingsManager.set_volume(&"SFX", 0)
	t.check(AudioServer.is_bus_mute(sfx), "[companion] SFX volume 0% mutes the petting sound")
	SettingsManager.set_volume(&"SFX", volume)
	await t.screenshot("26_pet_%s" % name)
	await t.get_tree().create_timer(ShipCompanion.REACTION_SECONDS + 0.2).timeout
	t.check(not companion.is_reacting(), "[companion] the reaction is brief")


# --- Sleep ---------------------------------------------------------------------------------

func _test_sleep_dialog() -> void:
	SettingsManager.set_sleep_hours(SettingsManager.DEFAULT_SLEEP_HOURS, false)  # the dialog remembers the last choice (Cozy Polish)
	await _move_player_to(Vector2(276, 0))
	await t.press_action(&"interact")
	var menu := app.modals.get_top() as SleepMenu
	if not t.check(menu != null, "[sleep] the berth opens the sleep dialog"):
		return
	t.check_eq(menu.hours, SleepMenu.DEFAULT_HOURS, "[sleep] it starts at 6 hours")
	var decrease := _button(menu, "DecreaseButton")
	var increase := _button(menu, "IncreaseButton")
	for i in 3:
		await t.click(increase)
	t.check_eq(menu.hours, 9, "[sleep] the right arrow adds an hour at a time")
	t.check_eq((menu.find_child("DurationLabel", true, false) as Label).text, "9 hours", "[sleep] the duration is shown")
	t.check((menu.find_child("WakeLabel", true, false) as Label).text.contains(
		Simulation.format_game_time(GameSession.get_game_time() + 9 * 3600.0)), "[sleep] the wake-up time is shown")
	await t.screenshot("27_sleep_dialog")
	for i in 20:
		menu.change_hours(1)
	t.check(menu.hours == SleepMenu.MAX_HOURS and increase.disabled, "[sleep] at most 12 hours (right arrow disabled)")
	for i in 20:
		if not decrease.disabled:
			await t.click(decrease)
	t.check(menu.hours == SleepMenu.MIN_HOURS and decrease.disabled, "[sleep] at least 1 hour (left arrow disabled)")
	await t.press_action(&"pause")
	t.check(app.modals.is_empty(), "[sleep] Esc cancels")


func _test_sleep_from_cabin() -> void:
	await _move_player_to(Vector2(-110, 0))
	SettingsManager.set_sleep_hours(SettingsManager.DEFAULT_SLEEP_HOURS, false)  # the dialog remembers the last choice (Cozy Polish)
	var before := GameSession.get_game_time()
	app.open_sleep_menu()
	await t.frames(2)  # let the dialog lay out before clicking
	var menu := app.modals.get_top() as SleepMenu
	for i in 3:
		menu.change_hours(-1)
	await t.click(_button(menu, "SleepButton"))
	await _settle()
	t.check(is_equal_approx(GameSession.get_game_time() - before, 3.0 * 3600.0), "[sleep] 3 hours pass while moored")
	_check_woke_at_berth("after sleeping in port")


func _check_woke_at_berth(when: String) -> void:
	var area := app.router.current_screen as BoatArea
	t.check(area != null and area.area_id == SessionState.AREA_INTERIOR, "[sleep] wakes in the cabin %s" % when)
	if area:
		t.check(area.player.position.distance_to(WAKE_MARKER) < 1.0 and GameSession.get_player_position().distance_to(WAKE_MARKER) < 1.0,
			"[sleep] beside the V-berth %s" % when)
		var space := area.get_world_2d().direct_space_state
		var query := PhysicsShapeQueryParameters2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 20.0
		query.shape = circle
		query.transform = Transform2D(0.0, WAKE_MARKER)
		query.exclude = [area.player.get_rid()]
		t.check(space.intersect_shape(query).is_empty(), "[sleep] the wake-up spot is clear of furniture %s" % when)
		t.check(not area.player.test_move(Transform2D(0.0, WAKE_MARKER), Vector2(-130, 0)),
			"[sleep] the player can walk from the berth back into the cabin %s" % when)


# --- Chart -----------------------------------------------------------------------------------

## Rectangles of the sidebar's fixed parts (and, with `with_course_tab`, the
## Course tab's buttons, which must not move while only live values change).
func _panel_geometry(map: WorldMap, with_course_tab := true) -> Dictionary:
	var geometry := {}
	var names := ["SidePanel", "Header", "Tabs", "Footer", "ApplyButton", "DiscardButton", "SetSailButton",
		"SleepButton", "BackButton"]
	if with_course_tab:
		names.append_array(["PlotButton", "RemoveWaypointButton", "ClearButton"])
	for control_name in names:
		var control := map.find_child(control_name, true, false) as Control
		geometry[control_name] = control.get_global_rect()
	return geometry


func _same_geometry(a: Dictionary, b: Dictionary) -> String:
	for key: String in a:
		var r1: Rect2 = a[key]
		var r2: Rect2 = b[key]
		if r1.position.distance_to(r2.position) > 0.5 or r1.size.distance_to(r2.size) > 0.5:
			return "%s moved from %s to %s" % [key, r1, r2]
	return ""


func _test_chart_panel_stability() -> void:
	# Underway at 20x with changing wind and propulsion.
	t.set_wind(270.0, 14.0)
	GameSession.plan_route_to(&"kiel")
	GameSession.depart()
	GameSession.set_time_scale(20)
	app.open_chart()
	await _settle()
	var map := app.router.current_screen as WorldMap
	if not t.check(map != null, "[chart] the chart opens"):
		return
	map.select_port(&"kiel")
	await _refresh_chart(map)
	var reference := _panel_geometry(map)
	var problems := PackedStringArray()
	var states := 0
	for step in 12:
		# 20x for a while, with the wind changing strength and side.
		Simulation.tick(1.0)
		t.set_wind(270.0 + step * 25.0, 2.0 + step * 2.5)
		Simulation.evaluate_propulsion(true, true)
		await _refresh_chart(map)
		var diff := _same_geometry(reference, _panel_geometry(map))
		if not diff.is_empty():
			problems.append(diff)
		states += 1
	var modes := {}
	for mode in [PropulsionState.MODE_SAIL, PropulsionState.MODE_ENGINE]:
		var forced := GameSession.get_propulsion()
		forced.mode = mode
		forced.speed_kn = 5.0 if mode == PropulsionState.MODE_ENGINE else 9.9
		GameSession.set_propulsion(forced)
		await _refresh_chart(map)
		modes[mode] = (map.find_child("StatusLabel", true, false) as Label).text
		var diff := _same_geometry(reference, _panel_geometry(map))
		if not diff.is_empty():
			problems.append(diff)
	t.check(problems.is_empty(), "[chart] the panel and its buttons stay put while time, wind, speed, ETA and propulsion change (%d states)%s"
		% [states + 2, "" if problems.is_empty() else ": " + problems[0]])
	t.check("under engine" in modes[PropulsionState.MODE_ENGINE] and "under sail" in modes[PropulsionState.MODE_SAIL],
		"[chart] sailing and motoring are both shown")

	# Different destinations: long and short names and descriptions (the
	# Course tab's own content may reflow; the sidebar and footer may not).
	problems.clear()
	var fixed_reference := _panel_geometry(map, false)
	for port in [&"gothenburg", &"reykjavik", &"kiel", &"piraeus", &"helsinki"]:
		map.select_port(port)
		await _refresh_chart(map)
		var diff := _same_geometry(fixed_reference, _panel_geometry(map, false))
		if not diff.is_empty():
			problems.append("%s: %s" % [port, diff])
	t.check(problems.is_empty(), "[chart] selecting other destinations does not move the sidebar, header or footer%s" % ("" if problems.is_empty() else ": " + problems[0]))
	var details := map.find_child("SelectionDetails", true, false) as Label
	t.check(not details.text.is_empty() and details.get_visible_line_count() == details.get_line_count(),
		"[chart] long texts are shown in full (wrapped inside the tab)")

	# Editing the course (weather list and course status change).
	map.select_port(&"kiel")
	map.plot_course_to(&"gothenburg")
	await _refresh_chart(map)
	var diff_edit := _same_geometry(fixed_reference, _panel_geometry(map, false))
	t.check(diff_edit.is_empty(), "[chart] a new draft course with its weather does not move the sidebar or its footer%s" % ("" if diff_edit.is_empty() else ": " + diff_edit))
	map.discard_changes()
	await _refresh_chart(map)
	await t.screenshot("28_chart_panel_underway")

	# Interface scales: everything still fits on screen and nothing moves while data changes.
	for scale in [0.8, 1.3]:
		SettingsManager.set_ui_scale(scale)
		await _refresh_chart(map)
		var scaled := _panel_geometry(map)
		var screen := Rect2(Vector2.ZERO, t.get_viewport().get_visible_rect().size)
		Simulation.tick(3.0)
		t.set_wind(90.0, 18.0)
		Simulation.evaluate_propulsion(true, true)
		await _refresh_chart(map)
		var moved := _same_geometry(scaled, _panel_geometry(map))
		var back := map.find_child("BackButton", true, false) as Control
		var panel := map.find_child("SidePanel", true, false) as Control
		var panel_rect := panel.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, panel.size)
		t.check(moved.is_empty() and screen.encloses(panel_rect.grow(-1.0)),
			"[chart] at %d%% interface scale the panel fits and stays stable%s" % [roundi(scale * 100), "" if moved.is_empty() else ": " + moved])
		t.check(back.is_visible_in_tree(), "[chart] the Back button is reachable at %d%%" % roundi(scale * 100))
		if scale == 1.3:
			await t.screenshot("28b_chart_panel_scale_130")
	SettingsManager.set_ui_scale(1.0)
	GameSession.set_time_scale(1)
	await _refresh_chart(map)


func _refresh_chart(map: WorldMap) -> void:
	map._refresh()
	await t.frames(3)


func _test_sleep_from_chart() -> void:
	var map := app.router.current_screen as WorldMap
	if not t.check(map != null, "(setup) still at the chart"):
		return
	t.set_wind(270.0, 14.0)
	SettingsManager.set_sleep_hours(SettingsManager.DEFAULT_SLEEP_HOURS, false)  # the dialog remembers the last choice (Cozy Polish)
	var snapshot := GameSession.get_state_snapshot()
	await t.click(_button(map, "SleepButton"))
	await t.frames(2)
	var menu := app.modals.get_top() as SleepMenu
	if not t.check(menu != null, "[sleep] the chart's Sleep button opens the same sleep dialog"):
		return
	for i in 4:
		menu.change_hours(-1)  # 2 hours
	await t.click(_button(menu, "SleepButton"))
	await _settle()
	_check_woke_at_berth("after sleeping from the chart")
	var from_chart := GameSession.get_voyage_progress_nm()
	var chart_time := GameSession.get_game_time()
	# The same sleep started directly from the simulation gives the same result.
	GameSession.replace_state(snapshot)
	Simulation.sleep(2.0)
	t.check(absf(GameSession.get_voyage_progress_nm() - from_chart) < 1e-9 and GameSession.get_game_time() == chart_time,
		"[sleep] sleeping from the chart advances the voyage exactly like any other sleep (%.3f nm)" % from_chart)
	t.check(chart_time - snapshot.game_time == 2.0 * 3600.0, "[sleep] 2 hours passed")


func _test_interrupted_sleep() -> void:
	# A weather warning wakes the crew early (calm: 5 kn under engine to Kiel).
	t.use_calm_wind()
	# A fixed strong-wind area on the course (a fixture of the weather model).
	WeatherFixtures.use([WeatherFixtures.gale("test_strong_winds", Vector2(12.2, 54.78), 9.0, 26.0,
		SessionState.get_start_time() - 3600.0, 24.0 * 365.0)])
	GameSession.start_new_session()
	t.board(&"starling_33")  # walks written for the Wing 33
	GameSession.enter_boat_area(SessionState.AREA_EXTERIOR, &"start")
	app._show_current_boat_area()
	await _settle()
	GameSession.plan_route_to(&"kiel")
	GameSession.depart()
	var start := GameSession.get_game_time()
	app.sleep_for(12.0)
	await _settle()
	var slept := GameSession.get_game_time() - start
	t.check(slept < 12.0 * 3600.0 and app.hud.is_warning_visible(), "[sleep] a weather warning cuts the sleep short (%s)" % Simulation.format_duration(slept))
	t.check(_toast_contains("woken") and _toast_contains("weather warning"), "[sleep] the reason is explained")
	_check_woke_at_berth("after a weather warning (sleep started on deck)")
	t.check(absf(GameSession.get_voyage_progress_nm() - slept / 3600.0 * 5.0) < 1e-6, "[sleep] the boat moved exactly as far as the time slept")
	app.hud.hide_warning()
	WeatherFixtures.clear()

	# Arrival wakes the crew too.
	for i in 6:
		app.sleep_for(12.0)
		await _settle()
		if not GameSession.is_underway():
			break
	t.check(GameSession.get_location_id() == &"kiel" and _toast_contains("arrived"), "[sleep] arrival ends the sleep")
	_check_woke_at_berth("after arriving")
	await t.screenshot("29_woke_at_v_berth")


# --- Helm and sails --------------------------------------------------------------------------

func _test_helm_and_sails() -> void:
	t.set_wind(185.0, 14.0)  # a head wind out of Copenhagen towards Kiel: motoring
	GameSession.start_new_session()
	t.board(&"starling_33")  # walks written for the Wing 33
	GameSession.enter_boat_area(SessionState.AREA_EXTERIOR, &"start")
	GameSession.plan_route_to(&"kiel")
	GameSession.depart()
	Simulation.advance(2.0 * 3600.0)
	app._show_current_boat_area()
	await _settle()
	var deck := app.router.current_screen as BoatArea
	var rig := deck.get_node("SailRig") as SailRig
	t.check(GameSession.is_motoring() and rig.is_furled(), "(setup) motoring with sails furled")
	await _move_player_to(Vector2(-448, 0))
	t.check_eq(app.hud.get_prompt(), "Check sail configuration", "[helm] underway the helm offers to check the sails")
	# Furled sails do not move.
	var furled_a: Dictionary = rig.get_shape(0.0)
	var furled_b: Dictionary = rig.get_shape(3.7)
	t.check(furled_a.main.clew == furled_b.main.clew, "[sails] furled sails do not move")

	t.set_wind(320.0, 15.0)  # the wind backs: now a good breeze
	await t.press_action(&"interact")
	t.check(GameSession.are_sails_set(), "[helm] the check sets the sails in the better wind")
	t.check(_toast_contains("Sailing conditions favourable"), "[helm] and says so")
	await t.wait_until(func() -> bool: return not rig.is_furled() and absf(rig.set_amount - 1.0) < 0.01, 5.0)
	t.check(not AudioManager.is_loop_playing(app.ENGINE_LOOP), "[helm] the engine sound stops")
	app.hud.refresh()
	t.check((app.hud.find_child("PropulsionLabel", true, false) as Label).text.begins_with("Under sail"), "[helm] the HUD shows sailing")
	await t.press_action(&"interact")
	t.check(GameSession.are_sails_set() and _toast_contains("Sails are drawing well"), "[helm] checking again changes nothing")

	# Sail motion: subtle, continuous, on the leeward side, never feeding the simulation.
	_check_motion(rig, "main", 0.3, 12.0)
	_check_motion(rig, "jib", 0.3, 12.0)
	var lee := -1.0 if GameSession.get_propulsion().true_wind_angle >= 0.0 else 1.0
	var leeward := true
	for i in 40:
		var shape: Dictionary = rig.get_shape(i * 0.37)
		leeward = leeward and signf(shape.main.clew.y) == lee and signf(shape.jib.clew.y) == lee
	t.check(leeward, "[sails] the moving sails always stay on the leeward side")
	var state_before := GameSession.get_propulsion().to_dict()
	await t.frames(30)
	t.check(GameSession.get_propulsion().to_dict() == state_before, "[sails] sail motion never changes the propulsion state or speed")
	await t.screenshot("30_deck_sailing_motion")

	# The spinnaker: large, ahead of the bow, attached to pole, halyard and sheet.
	var spinnaker_state := GameSession.get_propulsion()
	spinnaker_state.true_wind_angle = 150.0
	spinnaker_state.spinnaker = true
	GameSession.set_propulsion(spinnaker_state)
	await t.wait_until(func() -> bool: return absf(rig.spinnaker_amount - 1.0) < 0.01, 5.0)
	await t.frames(60)
	lee = -1.0  # wind on the starboard quarter: leeward is port
	var kite: Dictionary = rig.get_shape().spinnaker
	var front_mid: Vector2 = kite.front[kite.front.size() / 2]
	t.check(front_mid.x > 650.0, "[spinnaker] it flies well ahead of the bow (leading edge at x=%d, bow at 500)" % roundi(front_mid.x))
	t.check(absf((kite.tack as Vector2).distance_to(rig.mast) - rig.spinnaker_pole) < 0.5,
		"[spinnaker] its tack is at the end of the pole from the mast")
	t.check(signf(kite.tack.y) == -signf(kite.clew.y) and signf(kite.clew.y) == lee,
		"[spinnaker] pole to windward, clew sheeted to leeward")
	var width: float = (kite.tack as Vector2).distance_to(kite.clew)
	t.check(width > 330.0 and kite.depth > 480.0, "[spinnaker] it stays large (%d wide, %d deep)" % [roundi(width), roundi(kite.depth)])
	_check_motion(rig, "spinnaker", 0.5, 40.0)
	await t.screenshot("31_deck_spinnaker_refined")
	await _set_wind_and_check(rig)


func _set_wind_and_check(rig: SailRig) -> void:
	# Back to motoring: sails furl again (and stop moving).
	var motoring := GameSession.get_propulsion()
	motoring.mode = PropulsionState.MODE_ENGINE
	motoring.spinnaker = false
	GameSession.set_propulsion(motoring)
	await t.wait_until(func() -> bool: return rig.is_furled() and not rig.is_spinnaker_visible(), 6.0)
	t.check(rig.is_furled() and AudioManager.is_loop_playing(app.ENGINE_LOOP), "[sails] motoring furls the sails and runs the engine sound")


## The sail named `sail` moves a little over 10 s of animation: at least
## `min_px` and at most `max_px` (cosmetic only).
func _check_motion(rig: SailRig, sail: String, min_px: float, max_px: float) -> void:
	var key := "clew" if sail != "spinnaker" else "head"
	var reference: Vector2 = rig.get_shape(0.0)[sail][key]
	var largest := 0.0
	var largest_step := 0.0
	var previous := reference
	for i in range(1, 201):
		var point: Vector2 = rig.get_shape(i * 0.05)[sail][key]
		largest = maxf(largest, point.distance_to(reference))
		largest_step = maxf(largest_step, point.distance_to(previous))
		previous = point
	t.check(largest >= min_px and largest <= max_px, "[sails] the %s moves gently (up to %.1f px over 10 s)" % [sail, largest])
	t.check(largest_step < 1.5, "[sails] the %s moves smoothly, no jitter (max %.2f px per frame)" % [sail, largest_step])


# --- Persistence -----------------------------------------------------------------------------

func _test_companion_persistence() -> void:
	app.router.change_screen(GameSession.get_vessel_definition().cabin_scene, app._connect_boat_area)
	GameSession.enter_boat_area(SessionState.AREA_INTERIOR, &"start")
	await _settle()
	_set_companion(CompanionState.KIND_CAT, &"nav_station")
	var saved_companion := GameSession.get_companion().to_dict()
	var saved_propulsion := GameSession.get_propulsion().to_dict()
	t.check_eq(SaveManager.save_to_slot(2, GameSession.get_state_snapshot()), OK, "[persistence] saved")
	# Scene changes never duplicate the companion.
	for area in [&"exterior", &"interior"]:
		app._on_area_change_requested(area, &"start" if area == &"exterior" else &"from_deck")
		await _settle()
		t.check_eq(_companion_count(), 1 if area == &"interior" else 0, "[companion] %s: %s" % [area,
			"one companion in the cabin" if area == &"interior" else "the companion stays below deck"])
	app.open_chart()
	await _settle()
	app.close_chart()
	await _settle()
	t.check_eq(_companion_count(), 1, "[companion] still exactly one after the chart")
	app.show_main_menu()
	await _settle()
	app.load_slot(2)
	await _settle()
	t.check_eq(GameSession.get_companion().to_dict(), saved_companion, "[persistence] the companion's kind, spot and schedule are restored")
	# Floats may come back one unit in the last place off through JSON.
	var restored := GameSession.get_propulsion().to_dict()
	var same := restored.keys() == saved_propulsion.keys() and restored.keys().all(func(k: String) -> bool:
		return is_equal_approx(restored[k], saved_propulsion[k]) if restored[k] is float else restored[k] == saved_propulsion[k])
	t.check(same, "[persistence] the propulsion state is restored (%s)" % [restored])
	t.check(_companion() != null and _companion().spot == &"nav_station" and _companion_count() == 1, "[persistence] it rests where it was")

	# An Iteration 003 save (v3) gets the default companion.
	var data: Dictionary = GameSession.get_state_snapshot().to_dict()
	data.erase("companion")
	var v3 := {"format": "next_harbor_save", "version": 3, "game_version": "0.3.0",
		"saved_at_unix": 1790000000.0, "saved_at_utc": "2026-09-21T12:53:20Z", "session": data}
	var path := SaveManager.save_dir.path_join("slot_3.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(v3, "", true, true))
	file.close()
	var loaded := SaveManager.load_from_slot(3)
	t.check(loaded.is_ok() and loaded.state.companion.kind == CompanionState.DEFAULT_KIND,
		"[persistence] an Iteration 003 save loads with the default companion (a cat)")
	if loaded.is_ok():
		t.check(loaded.state.companion.spot in CompanionState.get_spot_ids(CompanionState.KIND_CAT)
			and loaded.state.companion.next_move_time > loaded.state.game_time, "[persistence] resting in a valid spot with a sensible schedule")
	DirAccess.remove_absolute(path)
	SaveManager.delete_slot(2)


func _test_dog_game() -> void:
	app.show_main_menu()
	await _settle()
	await t.click(_button(app.router.current_screen, "NewGameButton"))
	await t.click(_button(app.modals.get_top(), "DogButton"))
	await t.click(_button(app.modals.get_top(), "StartButton"))
	await _settle()
	t.check(GameSession.get_companion().kind == CompanionState.KIND_DOG and _companion().kind == CompanionState.KIND_DOG,
		"[companion] a new game with the dog")
	await t.frames(2)
	await t.screenshot("32_cabin_dog")
	await _test_petting(CompanionState.KIND_DOG)
	app.show_main_menu()
	await _settle()


# --- Helpers ---------------------------------------------------------------------------------

func _set_companion(kind: StringName, spot: StringName) -> void:
	var state := GameSession.get_state_snapshot()
	state.companion = CompanionState.create(kind, state.game_time)
	state.companion.spot = spot
	GameSession.replace_state(state)


func _companion() -> ShipCompanion:
	var area := app.router.current_screen as Node
	return area.find_child("Companion", true, false) as ShipCompanion if area else null


## Companions shown (since Iteration 18 the deck keeps a hidden companion of its
## own, which comes up only when the animal follows the captain).
func _companion_count() -> int:
	var count := 0
	for node in t.get_tree().root.find_children("*", "", true, false):
		if node is ShipCompanion and not (node as ShipCompanion).preview and (node as ShipCompanion).is_visible_in_tree():
			count += 1
	return count


## A walkable place within reach of `at` (tries around it).
func _free_spot_near(at: Vector2) -> Vector2:
	for offset in [Vector2(0, 42), Vector2(0, -42), Vector2(42, 0), Vector2(-42, 0), Vector2(30, 30), Vector2(-30, 30),
			Vector2(30, -30), Vector2(-30, -30)]:
		var area := app.router.current_screen as BoatArea
		var space := area.get_world_2d().direct_space_state
		var query := PhysicsShapeQueryParameters2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 20.0
		query.shape = circle
		query.transform = Transform2D(0.0, at + offset)
		query.exclude = [area.player.get_rid()]
		if space.intersect_shape(query).is_empty() and area.walkable_bounds.has_point(at + offset):
			return at + offset
	return at + Vector2(0, 42)


func _sfx_player_with(stream: AudioStream) -> AudioStreamPlayer:
	for child in AudioManager.get_children():
		var player := child as AudioStreamPlayer
		if player and player.stream == stream and player.playing:
			return player
	return null


func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)


func _move_player_to(position: Vector2) -> void:
	var area := app.router.current_screen as BoatArea
	area.player.position = position
	await t.physics_frames(3)


func _button(root: Node, button_name: String) -> Button:
	return root.find_child(button_name, true, false) as Button


func _toast_contains(text: String) -> bool:
	for message in app.toasts.get_messages():
		if text in message:
			return true
	return false
