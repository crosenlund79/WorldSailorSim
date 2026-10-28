extends RefCounted
## Iteration 006, Checkpoint A: the Captain's Log. Statistics, visited
## harbours and voyage records from the authoritative voyage events (arrival,
## rescue), changes of course, determinism, the bounded history, save/load,
## migration of version 7 saves, and the log panel in the real application.

const APP_SCENE := preload("res://src/app/app.tscn")
const HOUR := 3600.0

var t: Node
var app: Node
var logged: Array = []


func run(runner: Node) -> void:
	t = runner
	Simulation.auto_advance = false
	t.use_calm_wind()
	WeatherFixtures.clear()
	GameSession.voyage_logged.connect(_on_logged)
	_test_new_game()
	_test_arrival()
	_test_change_of_course()
	_test_rescue()
	_test_determinism()
	_test_bounded_history()
	_test_persistence()
	_test_migration()
	GameSession.voyage_logged.disconnect(_on_logged)
	GameSession.end_session()

	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	app.start_new_game()
	await _settle()
	await _test_log_panel()
	Simulation.auto_advance = true
	app.queue_free()
	await t.frames(2)
	GameSession.end_session()
	WeatherFixtures.clear()
	t.use_calm_wind()


func _on_logged(record: Dictionary, new_harbour: bool) -> void:
	logged.append([record, new_harbour])


func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)


func _new_game() -> void:
	WeatherFixtures.use([])
	GameSession.start_new_session()
	logged.clear()


## Plans and sails to `port`, advancing until arrival. Returns the route length.
func _sail_to(port: StringName) -> float:
	t.check_eq(GameSession.plan_route_to(port), "", "(setup) course to %s" % port)
	var total := GameSession.get_planned_route().get_distance_nm()
	t.check_eq(GameSession.depart(), "", "(setup) underway to %s" % port)
	_finish_voyage()
	return total


func _finish_voyage() -> void:
	var guard := 40
	while GameSession.is_underway() and guard > 0:
		guard -= 1
		Simulation.advance(24.0 * HOUR, true)


# --- New game ---------------------------------------------------------------------------

func _test_new_game() -> void:
	_new_game()
	var log := GameSession.get_captains_log()
	t.check(log.get_distinct_harbours() == 1 and log.has_visited(&"copenhagen"), "[log] a new game lists its start harbour, Copenhagen, as visited")
	t.check(is_equal_approx(float(log.visited["copenhagen"].first), GameSession.get_game_time()) and int(log.visited["copenhagen"].arrivals) == 0,
		"[log] the start harbour: first seen at the start time, no arrival")
	t.check(log.total_nm == 0.0 and log.voyages_completed == 0 and log.arrivals == 0 and log.voyages.is_empty() and log.longest.is_empty(),
		"[log] no distance, voyages, arrivals or passages yet")
	# Planning a course is not a visit.
	GameSession.plan_route_to(&"kiel")
	t.check(not GameSession.get_captains_log().has_visited(&"kiel"), "[log] plotting a course to Kiel does not visit it")


# --- Arrival ------------------------------------------------------------------------------

func _test_arrival() -> void:
	_new_game()
	GameSession.plan_route_to(&"kiel")
	var total := GameSession.get_planned_route().get_distance_nm()
	GameSession.depart()
	var departed := GameSession.get_game_time()
	Simulation.advance(3.0 * HOUR)
	var progress := GameSession.get_voyage_progress_nm()
	t.check(progress > 5.0 and absf(GameSession.get_voyage_sailed_nm() - progress) < 1e-9,
		"[log] underway: the distance sailed follows the voyage (%.2f nm)" % progress)
	t.check(absf(GameSession.get_total_nm_sailed() - progress) < 1e-9 and GameSession.get_captains_log().voyages.is_empty(),
		"[log] the total includes the voyage under way; nothing is recorded before it ends")
	_finish_voyage()
	var log := GameSession.get_captains_log()
	t.check(GameSession.get_location_id() == &"kiel" and logged.size() == 1, "[log] arriving in Kiel records the voyage once")
	t.check(absf(log.total_nm - total) < 1e-6 and absf(GameSession.get_total_nm_sailed() - total) < 1e-6,
		"[log] the distance sailed equals the course, %.2f nm" % total)
	t.check(log.voyages_completed == 1 and log.arrivals == 1 and log.get_distinct_harbours() == 2 and log.has_visited(&"kiel"),
		"[log] 1 voyage, 1 arrival, 2 harbours")
	var record: Dictionary = log.voyages[0]
	t.check(record.from == "copenhagen" and record.to == "kiel" and record.vessel == "arctic_wanderer_26" and record.outcome == "arrived"
		and is_equal_approx(float(record.departed), departed) and is_equal_approx(float(record.ended), GameSession.get_game_time())
		and absf(float(record.nm) - total) < 1e-6 and record.complete == true,
		"[log] the record: Copenhagen → Kiel, departure and arrival times, distance, boat, arrived")
	t.check(absf(log.get_longest_nm() - total) < 1e-6, "[log] it is the longest passage so far")
	t.check(logged[0][1] == true and is_equal_approx(float(log.visited["kiel"].first), GameSession.get_game_time())
		and int(log.visited["kiel"].arrivals) == 1, "[log] Kiel is a new harbour, first visited on arrival")
	# Back to Copenhagen: an arrival, but not a new harbour.
	logged.clear()
	var back := _sail_to(&"copenhagen")
	log = GameSession.get_captains_log()
	t.check(log.get_distinct_harbours() == 2 and log.arrivals == 2 and log.voyages_completed == 2 and logged.size() == 1 and logged[0][1] == false,
		"[log] returning to Copenhagen: 2 arrivals, still 2 distinct harbours, not new")
	t.check_eq(int(log.visited["copenhagen"].arrivals), 1, "[log] Copenhagen now has 1 arrival")
	t.check(absf(log.total_nm - (total + back)) < 1e-6, "[log] the total adds up both passages (%.2f nm)" % log.total_nm)
	# Waiting, sleeping and working in harbour add nothing.
	var before := log.to_dict()
	Simulation.advance(10.0 * HOUR)
	Simulation.sleep(4.0)
	Simulation.work(2)
	t.check_eq(GameSession.get_captains_log().to_dict(), before, "[log] time in harbour (waiting, sleep, work) changes nothing")


# --- Change of course ---------------------------------------------------------------------

func _test_change_of_course() -> void:
	_new_game()
	GameSession.plan_route_to(&"kiel")
	GameSession.depart()
	Simulation.advance(4.0 * HOUR)
	var first_leg := GameSession.get_voyage_progress_nm()
	t.check_eq(GameSession.change_course(&"gothenburg", []), "", "(setup) course changed to Gothenburg at sea")
	var second_leg := GameSession.get_voyage_total_nm()
	t.check(absf(GameSession.get_voyage_sailed_nm() - first_leg) < 1e-9, "[log] a change of course keeps the distance already sailed")
	_finish_voyage()
	var log := GameSession.get_captains_log()
	var record: Dictionary = log.voyages[0]
	t.check(record.from == "copenhagen" and record.to == "gothenburg" and absf(float(record.nm) - (first_leg + second_leg)) < 1e-6,
		"[log] one voyage, Copenhagen → Gothenburg, %.1f nm = both legs" % float(record.nm))
	t.check(not log.has_visited(&"kiel") and log.has_visited(&"gothenburg"), "[log] the abandoned destination is not visited")


# --- Rescue ---------------------------------------------------------------------------------

func _test_rescue() -> void:
	_new_game()
	_sail_to(&"kiel")
	var before := GameSession.get_captains_log()
	GameSession.plan_route_to(&"copenhagen")
	GameSession.depart()
	Simulation.advance(2.0 * HOUR)
	GameSession.set_condition_for_testing(1.0)
	WeatherFixtures.use([WeatherFixtures.gale("fx_log", GameSession.get_vessel_position(), 80.0, 52.0,
		GameSession.get_game_time() - HOUR, 96.0, 0.0, 0.0, 250.0)])
	logged.clear()
	var result := Simulation.advance(6.0 * HOUR)
	var log := GameSession.get_captains_log()
	t.check(result.rescued and GameSession.get_rescue_count() == 1 and logged.size() == 1, "(setup) the boat is lost and the crew rescued")
	var record: Dictionary = log.voyages[log.voyages.size() - 1]
	t.check(record.outcome == "rescued" and record.from == "kiel" and record.to == "copenhagen" and float(record.nm) > 5.0
		and float(record.damage) > 0.0 and int(record.worst_hazard) >= WeatherModel.HAZARD_DANGEROUS,
		"[log] the lost voyage is recorded: rescued, its distance, the damage and the storm")
	t.check(log.voyages_completed == before.voyages_completed and log.arrivals == before.arrivals
		and int(log.visited["copenhagen"].arrivals) == int(before.visited["copenhagen"].arrivals),
		"[log] a rescue is neither a completed voyage nor an arrival (the tow home does not count)")
	t.check(absf(log.total_nm - (before.total_nm + float(record.nm))) < 1e-6, "[log] the miles sailed before the loss still count")
	t.check(is_equal_approx(log.get_longest_nm(), before.get_longest_nm()), "[log] a lost voyage is not a 'longest passage'")
	# The rescue happens once: more time adds nothing.
	Simulation.advance(6.0 * HOUR)
	t.check(logged.size() == 1 and GameSession.get_captains_log().voyages.size() == log.voyages.size(), "[log] no second record afterwards")
	WeatherFixtures.use([])


# --- Determinism ------------------------------------------------------------------------------

func _test_determinism() -> void:
	var results := []
	for mode in ["large", "frames"]:
		_new_game()
		GameSession.plan_route_to(&"gothenburg")
		GameSession.depart()
		if mode == "large":
			Simulation.advance(9.0 * HOUR)
		else:
			for i in 9 * 60:
				Simulation.advance(60.0)
		results.append(GameSession.get_voyage_sailed_nm())
	t.check(absf(results[0] - results[1]) < 1e-6, "[log] the distance sailed is the same in one step or in 540 small ones (%s)" % [results])


# --- Bounded history ----------------------------------------------------------------------------

func _test_bounded_history() -> void:
	var log := CaptainsLog.create(&"copenhagen", 0.0)
	for i in 60:
		log.record_voyage({"from": "copenhagen", "to": "kiel" if i % 2 == 0 else "copenhagen", "departed": i * 100.0,
			"ended": i * 100.0 + 50.0, "nm": 10.0 + i, "vessel": "starling_33", "outcome": "arrived"})
	t.check(log.voyages.size() == CaptainsLog.MAX_VOYAGES and float(log.voyages[0].departed) == 1000.0,
		"[log] only the latest %d passages are kept (the oldest are dropped)" % CaptainsLog.MAX_VOYAGES)
	t.check(log.voyages_completed == 60 and log.arrivals == 60 and is_equal_approx(log.total_nm, 60.0 * 10.0 + 59.0 * 60.0 / 2.0)
		and is_equal_approx(log.get_longest_nm(), 69.0), "[log] totals and the longest passage still count every voyage")
	var size := JSON.stringify(log.to_dict()).length()
	t.check(size < 20000, "[log] a full log is small in a save (%d characters)" % size)


# --- Save and load --------------------------------------------------------------------------------

func _test_persistence() -> void:
	_new_game()
	_sail_to(&"kiel")
	GameSession.plan_route_to(&"copenhagen")
	GameSession.depart()
	Simulation.advance(3.0 * HOUR)
	var snapshot := GameSession.get_state_snapshot()
	t.check_eq(SaveManager.save_to_slot(2, snapshot), OK, "(setup) saved under way")
	var loaded := SaveManager.load_from_slot(2)
	t.check(loaded.is_ok(), "[log] the save loads (%s)" % loaded.error)
	if not loaded.is_ok():
		return
	t.check_eq(loaded.state.captains_log.to_dict(), snapshot.captains_log.to_dict(), "[log] the Captain's Log is saved and loaded exactly")
	t.check(absf(loaded.state.voyage.sailed_nm - snapshot.voyage.sailed_nm) < 1e-9 and loaded.state.voyage.departure_port_id == &"kiel"
		and loaded.state.voyage.fully_recorded, "[log] the voyage under way keeps its distance and departure harbour")
	_finish_voyage()
	var straight := GameSession.get_captains_log().to_dict()
	logged.clear()
	GameSession.replace_state(loaded.state)
	t.check(logged.is_empty(), "[log] loading records nothing")
	_finish_voyage()
	t.check_eq(GameSession.get_captains_log().to_dict(), straight, "[log] continuing after loading gives the same log as not saving")
	# Loading the arrived game again does not record the arrival again.
	SaveManager.save_to_slot(2, GameSession.get_state_snapshot())
	logged.clear()
	GameSession.replace_state(SaveManager.load_from_slot(2).state)
	Simulation.advance(5.0 * HOUR)
	t.check(logged.is_empty() and GameSession.get_captains_log().voyages_completed == 2, "[log] after loading an arrived game: no repeat record")
	# Invalid log data is refused.
	var data := GameSession.get_state_snapshot().to_dict()
	data.log.total_nm = -5.0
	var errors: Array[String] = []
	t.check(SessionState.from_dict(data, errors) == null and not errors.is_empty(), "[log] a negative distance is rejected (%s)" % [errors])
	SaveManager.delete_slot(2)


# --- Migration ------------------------------------------------------------------------------------

func _test_migration() -> void:
	# A version 7 save in Kiel, then one under way.
	_new_game()
	_sail_to(&"kiel")
	var v7: Dictionary = GameSession.get_state_snapshot().to_dict()
	v7.erase("log")
	_write_slot(3, 7, v7)
	var migrated := SaveManager.load_from_slot(3)
	t.check(migrated.is_ok(), "[migration] a version 7 save loads (%s)" % migrated.error)
	if migrated.is_ok():
		var log := migrated.state.captains_log
		t.check(log.get_distinct_harbours() == 2 and log.has_visited(&"copenhagen") and log.has_visited(&"kiel")
			and float(log.visited["kiel"].first) == CaptainsLog.UNKNOWN_TIME,
			"[migration] visited: Copenhagen (every game's start) and Kiel (where the boat lies), first visit unknown")
		t.check(log.voyages.is_empty() and log.total_nm == 0.0 and log.voyages_completed == 0 and log.arrivals == 0,
			"[migration] no voyages, distance or arrivals are invented")
		t.check(migrated.state.funds == GameSession.get_funds() and migrated.state.location_id == &"kiel",
			"[migration] everything else is kept")

	GameSession.plan_route_to(&"copenhagen")
	GameSession.depart()
	Simulation.advance(3.0 * HOUR)
	var underway: Dictionary = GameSession.get_state_snapshot().to_dict()
	underway.erase("log")
	for key in ["departure_port_id", "departure_position", "sailed_nm", "worst_hazard", "damage_percent", "fully_recorded"]:
		underway.navigation.voyage.erase(key)
	_write_slot(3, 7, underway)
	var at_sea := SaveManager.load_from_slot(3)
	t.check(at_sea.is_ok(), "[migration] a version 7 save under way loads (%s)" % at_sea.error)
	if at_sea.is_ok():
		var voyage := at_sea.state.voyage
		t.check(voyage.departure_port_id == &"kiel" and absf(voyage.sailed_nm - voyage.progress_nm) < 1e-9 and not voyage.fully_recorded,
			"[migration] the voyage: from its course's origin, distance = progress, earlier weather unknown")
		t.check(at_sea.state.captains_log.get_distinct_harbours() == 1, "[migration] at sea only Copenhagen is known as visited")
		logged.clear()
		GameSession.replace_state(at_sea.state)
		_finish_voyage()
		var log := GameSession.get_captains_log()
		t.check(logged.size() == 1 and log.voyages_completed == 1 and log.voyages[0].from == "kiel" and log.voyages[0].complete == false,
			"[migration] arriving afterwards records the voyage, marked as not fully recorded")
	SaveManager.delete_slot(3)


func _write_slot(slot: int, version: int, session: Dictionary) -> void:
	var wrapper := {"format": "next_harbor_save", "version": version, "game_version": "0.5.0",
		"saved_at_unix": 1790000000.0, "saved_at_utc": "2026-09-21T12:53:20Z", "session": session}
	DirAccess.make_dir_recursive_absolute(SaveManager.save_dir)
	var file := FileAccess.open(SaveManager.save_dir.path_join("slot_%d.json" % slot), FileAccess.WRITE)
	file.store_string(JSON.stringify(wrapper, "", true, true))
	file.close()


# --- The log panel --------------------------------------------------------------------------------

func _test_log_panel() -> void:
	WeatherFixtures.use([])
	_sail_to(&"kiel")
	_sail_to(&"gothenburg")
	await _settle()
	# (Gothenburg has a picture: the line is part of its Golden Harbour Moment card.)
	var line := "New harbour in the Captain's Log: Gothenburg (3 of %d visited)." % PortCatalog.get_default().ports.size()
	t.check(Array(app.toasts.get_messages()).filter(func(m: String) -> bool: return m.contains(line)).size() == 1,
		"[log ui] a first visit is announced once, briefly (%s)" % [app.toasts.get_messages()])
	_clear_toasts()
	t.press_action(&"captains_log")
	await t.frames(3)
	var menu := app.modals.get_top() as CaptainsLogMenu
	t.check(menu != null, "[log ui] L opens the Captain's Log")
	if menu == null:
		return
	t.check(app.get_tree().paused, "[log ui] the game is paused behind it")
	var stats := menu.find_child("Statistics", true, false)
	var log := GameSession.get_captains_log()
	t.check(menu.find_child("DistanceValue", true, false).text == "%.1f nm" % log.total_nm
		and menu.find_child("VoyagesValue", true, false).text == "2"
		and menu.find_child("HarboursValue", true, false).text == "3 of %d" % PortCatalog.get_default().ports.size()
		and menu.find_child("ArrivalsValue", true, false).text == "2"
		and menu.find_child("RescuesValue", true, false).text == "0" and stats != null,
		"[log ui] statistics: distance, 2 voyages, 3 harbours, 2 arrivals, no rescues")
	var newest: Label = menu.find_child("Passage0", true, false)
	t.check(newest != null and newest.text.begins_with("Kiel → Gothenburg") and newest.text.contains("arrived"),
		"[log ui] the newest passage is listed first: %s" % (newest.text if newest else "none"))
	t.check(menu.find_child("LongestValue", true, false).text.contains("→"), "[log ui] the longest passage is named")
	await t.screenshot("108_captains_log")
	menu.show_tab(CaptainsLogMenu.TAB_HARBOURS)
	await t.frames(2)
	var kiel: Label = menu.find_child("Harbour_kiel", true, false)
	t.check(kiel != null and kiel.text.contains("Kiel, Germany") and kiel.text.contains("1 arrival"), "[log ui] Harbours: Kiel, first visit and 1 arrival")
	var start: Label = menu.find_child("Harbour_copenhagen", true, false)
	t.check(start != null and start.text.contains("start harbour"), "[log ui] Copenhagen is the start harbour")
	# Iteration 17: grouped by country, with All / Visited / Not visited filters.
	menu.set_harbour_filter(CaptainsLogMenu.FILTER_NOT_VISITED)
	await t.frames(2)
	t.check(menu.find_child("Harbour_kiel", true, false) == null and menu.find_child("Harbour_helsingor", true, false) != null,
		"[log ui] visited harbours are not under 'Not visited'")
	menu.set_harbour_filter(CaptainsLogMenu.FILTER_VISITED)
	await t.frames(2)
	var listed := 0
	for label in menu.find_children("Harbour_*", "Label", true, false):
		listed += 1
	t.check(listed == GameSession.get_captains_log().get_distinct_harbours() and menu.find_child("Harbour_kiel", true, false) != null,
		"[log ui] 'Visited' lists exactly the %d harbours visited" % GameSession.get_captains_log().get_distinct_harbours())
	var germany := menu.find_child("Country_Germany", true, false) as Button
	t.check(germany != null and "1 of" in germany.text, "[log ui] countries show how many of their harbours were visited (%s)" % (germany.text if germany else "-"))
	menu.set_harbour_filter(CaptainsLogMenu.FILTER_ALL)
	await t.frames(2)
	var group := menu.find_child("Harbours_Germany", true, false) as Control
	var was := group.visible
	(menu.find_child("Country_Germany", true, false) as Button).pressed.emit()
	await t.frames(1)
	t.check(group.visible != was, "[log ui] a country opens and closes")
	(menu.find_child("Country_Germany", true, false) as Button).pressed.emit()
	await t.screenshot("109_captains_log_harbours")
	var size_before: Vector2 = menu.find_child("Panel", true, false).size
	menu.show_tab(CaptainsLogMenu.TAB_LOG)
	await t.frames(2)
	t.check(menu.find_child("Panel", true, false).size == size_before, "[log ui] the panel keeps its size between tabs")
	t.press_action(&"captains_log")
	await t.frames(3)
	t.check(app.modals.is_empty() and not app.get_tree().paused, "[log ui] L closes it again")
	# From the pause menu.
	app.open_pause_menu()
	await t.frames(2)
	var button: Button = app.modals.get_top().find_child("LogButton", true, false)
	t.check(button != null and button.text.begins_with("Captain's Log"), "[log ui] the pause menu has a Captain's Log button")
	if button:
		button.pressed.emit()
		await t.frames(2)
		t.check(app.modals.get_top() is CaptainsLogMenu, "[log ui] it opens the log")
	app.modals.clear()
	await t.frames(2)


func _clear_toasts() -> void:
	for panel in app.toasts.get_children():
		app.toasts.remove_child(panel)
		panel.queue_free()
