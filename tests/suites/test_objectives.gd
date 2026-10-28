extends RefCounted
## Iteration 006, Checkpoint B: sailing objectives and renown. The catalogue
## (handcrafted and generated, valid harbour references), progress, one-time
## and repeatable rewards paid once per voyage, rescues, save/load and
## migration, and the Objectives view in the real application.

const APP_SCENE := preload("res://src/app/app.tscn")
const HOUR := 3600.0

var t: Node
var app: Node
var awarded: Array = []


func run(runner: Node) -> void:
	t = runner
	Simulation.auto_advance = false
	t.use_calm_wind()
	WeatherFixtures.clear()
	GameSession.renown_awarded.connect(_on_awarded)
	_test_catalog()
	_test_invalid_definitions()
	_test_first_voyage()
	_test_repeatable()
	_test_no_double_payment()
	_test_rescue()
	_test_weather_arrival()
	_test_persistence()
	_test_migration()
	GameSession.renown_awarded.disconnect(_on_awarded)
	GameSession.end_session()

	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	app.start_new_game()
	await _settle()
	await _test_objectives_view()
	Simulation.auto_advance = true
	app.queue_free()
	await t.frames(2)
	GameSession.end_session()
	WeatherFixtures.clear()
	t.use_calm_wind()


func _on_awarded(awards: Array) -> void:
	awarded.append(awards)


func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)


func _new_game() -> void:
	WeatherFixtures.use([])
	GameSession.start_new_session()
	awarded.clear()


func _sail_to(port: StringName) -> float:
	t.check_eq(GameSession.plan_route_to(port), "", "(setup) course to %s" % port)
	var total := GameSession.get_planned_route().get_distance_nm()
	t.check_eq(GameSession.depart(), "", "(setup) underway to %s" % port)
	_finish_voyage()
	return total


func _finish_voyage() -> void:
	var guard := 60
	while GameSession.is_underway() and guard > 0:
		guard -= 1
		Simulation.advance(24.0 * HOUR, true)


func _ids(awards: Array) -> Array:
	var ids := awards.map(func(a: Dictionary) -> String: return a.id)
	ids.sort()
	return ids


# --- Catalogue -----------------------------------------------------------------------------

func _test_catalog() -> void:
	var catalog := ObjectiveCatalog.get_default()
	var ports := PortCatalog.get_default()
	# Secret achievements (Visual Identity V01) are counted in their own suite.
	var regular := catalog.objectives.filter(func(o: Dictionary) -> bool: return not o.secret).size()
	t.check(regular >= 10 and regular <= 20, "[objectives] %d objectives (about 10–15 asked)" % regular)
	var ids := {}
	var types := {}
	var valid := true
	for objective in catalog.objectives:
		valid = valid and not ids.has(objective.id) and ObjectiveCatalog.validate(_as_entry(objective), ports).is_empty()
		ids[objective.id] = true
		types[objective.type] = true
	t.check(valid, "[objectives] unique ids, every definition valid")
	t.check_eq(types.size(), ObjectiveCatalog.TYPES.size(), "[objectives] every objective type is used")
	var harbours_ok := catalog.objectives.all(func(o: Dictionary) -> bool:
		return o.type != ObjectiveCatalog.TYPE_VISIT_HARBOUR or ports.has_port(o.port))
	t.check(harbours_ok, "[objectives] every harbour named by an objective is in the harbour catalogue")
	t.check(catalog.get_objective(&"first_voyage").reward == 20 and catalog.get_objective(&"new_harbour").reward == 10
		and catalog.get_objective(&"distance_100").reward == 25, "[objectives] suggested rewards: first voyage 20, new harbour 10, 100 nm 25")
	var challenges := catalog.objectives.filter(func(o: Dictionary) -> bool: return o.category in ["challenge", "weather"] and not o.repeatable)
	t.check(not challenges.is_empty() and challenges.all(func(o: Dictionary) -> bool: return o.reward >= 30 and o.reward <= 50),
		"[objectives] challenges pay 30–50 renown")
	var categories := {}
	for objective in catalog.objectives:
		categories[objective.category] = true
	t.check(categories.has("introduction") and categories.has("exploration") and categories.has("challenge") and categories.has("weather"),
		"[objectives] introductory, exploration, challenge and weather objectives")
	var generated := catalog.objectives.filter(func(o: Dictionary) -> bool: return o.generated)
	var start := ports.get_port(&"copenhagen").get_geo_position()
	t.check(generated.size() == 3 and generated.all(func(o: Dictionary) -> bool:
		return GeoMath.distance_nm(start, ports.get_port(o.port).get_geo_position()) >= 600.0 and o.reward >= 30 and o.reward <= 50),
		"[objectives] 3 generated from the harbour catalogue: distant harbours (≥ 600 nm), 30–50 renown (%s)" % [generated.map(func(o: Dictionary) -> String: return "%s %d" % [o.port, o.reward])])
	t.check(catalog.euros_per_renown == 2, "[renown] the publishing rate comes from the data: €2 per renown")
	# The same catalogue again: identical (deterministic generation).
	var again := ObjectiveCatalog.load_from(ObjectiveCatalog.DEFAULT_PATH, ports)
	t.check_eq(again.objectives.map(func(o: Dictionary) -> String: return o.id), catalog.objectives.map(func(o: Dictionary) -> String: return o.id),
		"[objectives] generation is deterministic")


func _as_entry(objective: Dictionary) -> Dictionary:
	var entry := objective.duplicate()
	entry.type = String(objective.type)
	entry.port = String(objective.port)
	return entry


func _test_invalid_definitions() -> void:
	var ports := PortCatalog.get_default()
	t.check(not ObjectiveCatalog.validate({"id": "x", "type": "visit_harbour", "port": "atlantis", "reward": 10}, ports).is_empty(),
		"[objectives] a harbour that does not exist is refused")
	t.check(not ObjectiveCatalog.validate({"id": "x", "type": "fly", "reward": 10}, ports).is_empty(), "[objectives] an unknown type is refused")
	t.check(not ObjectiveCatalog.validate({"id": "x", "type": "total_distance", "target": 0, "reward": 10}, ports).is_empty(),
		"[objectives] a zero target is refused")
	t.check(not ObjectiveCatalog.validate({"id": "x", "type": "voyage_count", "target": 2, "reward": 0}, ports).is_empty(),
		"[objectives] a zero reward is refused")


# --- First voyage -----------------------------------------------------------------------------

func _test_first_voyage() -> void:
	_new_game()
	t.check(GameSession.get_lifetime_renown() == 0 and GameSession.get_unpublished_renown() == 0 and GameSession.get_objective_progress().completed.is_empty(),
		"[renown] a new game has no renown and nothing completed (the start harbour pays nothing)")
	GameSession.plan_route_to(&"kiel")
	GameSession.depart()
	Simulation.advance(20.0 * HOUR)
	t.check(awarded.is_empty() and GameSession.get_lifetime_renown() == 0, "[renown] sailing 100 nm pays nothing until the voyage ends")
	_finish_voyage()
	t.check_eq(awarded.size(), 1, "[renown] arriving pays once")
	var ids := _ids(awarded[0]) if awarded.size() == 1 else []
	t.check_eq(ids, ["clean_150", "distance_100", "first_voyage", "new_harbour", "visit_kiel"],
		"[objectives] Kiel completes: first voyage, Kiel, 100 nm, a new harbour and 150 nm without damage")
	t.check(GameSession.get_lifetime_renown() == 100 and GameSession.get_unpublished_renown() == 100,
		"[renown] 20 + 15 + 25 + 10 + 30 = 100 renown, all unpublished (%d)" % GameSession.get_lifetime_renown())
	var progress := GameSession.get_objective_progress()
	t.check(is_equal_approx(float(progress.completed["first_voyage"].first), GameSession.get_game_time()) and progress.recent.size() == 5,
		"[renown] the completions are dated and listed")
	# Back to Copenhagen: an arrival, but nothing new.
	awarded.clear()
	_sail_to(&"copenhagen")
	t.check(awarded.is_empty() and GameSession.get_lifetime_renown() == 100,
		"[renown] sailing back to the start harbour pays nothing (not new, one-time objectives done)")
	# Leaving and returning again and again earns nothing.
	for i in 2:
		_sail_to(&"kiel")
		_sail_to(&"copenhagen")
	var paid := GameSession.get_objective_progress()
	t.check(GameSession.get_lifetime_renown() == 130 and paid.is_completed(&"voyages_5") and not paid.is_completed(&"harbours_5"),
		"[renown] four more Kiel trips: only 'Regular passages' (5 voyages, +30), no repeated harbour rewards (%d)" % GameSession.get_lifetime_renown())
	var log := GameSession.get_captains_log()
	var harbours := ObjectiveCatalog.get_progress(ObjectiveCatalog.get_default().get_objective(&"harbours_5"), log, GameSession.get_total_nm_sailed())
	t.check(harbours == [2.0, 5.0], "[objectives] progress: 2 of 5 harbours (%s)" % [harbours])
	var miles := ObjectiveCatalog.get_progress(ObjectiveCatalog.get_default().get_objective(&"distance_1000"), log, GameSession.get_total_nm_sailed())
	t.check(miles[0] > 900.0 and miles[0] < 1000.0 and miles[1] == 1000.0, "[objectives] progress: %.0f of 1,000 nm" % miles[0])


# --- Repeatable --------------------------------------------------------------------------------

func _test_repeatable() -> void:
	_new_game()
	var out := _sail_to(&"helsinki")
	t.check(out >= 300.0, "(setup) Copenhagen → Helsinki is %.0f nm" % out)
	var progress := GameSession.get_objective_progress()
	t.check(progress.get_count(&"blue_water") == 1 and progress.get_count(&"passage_200") == 1,
		"[objectives] a %.0f nm passage completes 'Offshore passage' and the repeatable 'Blue-water passage'" % out)
	var before := GameSession.get_lifetime_renown()
	awarded.clear()
	_sail_to(&"copenhagen")
	progress = GameSession.get_objective_progress()
	t.check(progress.get_count(&"blue_water") == 2 and progress.get_count(&"passage_200") == 1 and _ids(awarded[0]).has("blue_water"),
		"[objectives] the return passage pays 'Blue-water' again (×2), 'Offshore' stays once")
	t.check(_ids(awarded[0]) == ["blue_water", "distance_1000"] and GameSession.get_lifetime_renown() - before == 65,
		"[renown] the return pays the repeat (15) and, now past 1,000 nm in all, 'A thousand miles' (50): +%d" % (GameSession.get_lifetime_renown() - before))
	t.check(is_equal_approx(float(progress.completed["blue_water"].last_event), GameSession.get_game_time()),
		"[objectives] the repeat remembers the voyage it paid for")


# --- No double payment ------------------------------------------------------------------------

func _test_no_double_payment() -> void:
	var catalog := ObjectiveCatalog.get_default()
	var log := CaptainsLog.create(&"copenhagen", 0.0)
	var record := {"from": "copenhagen", "to": "kiel", "departed": 0.0, "ended": 1000.0, "nm": 320.0, "vessel": "starling_33",
		"outcome": "arrived", "worst_hazard": 0, "damage": 0.0, "complete": true}
	var new_harbour := log.record_voyage(record)
	var progress := ObjectiveProgress.new()
	var first := catalog.evaluate(log, record, new_harbour, progress)
	for award in first:
		progress.award(StringName(award.id), award.title, award.reward, 1000.0)
	var again := catalog.evaluate(log, record, new_harbour, progress)
	t.check(not first.is_empty() and again.is_empty(), "[renown] evaluating the same voyage again pays nothing (%d then %d)" % [first.size(), again.size()])
	var later := record.duplicate()
	later.ended = 2000.0
	var repeat := catalog.evaluate(log, later, false, progress)
	t.check(_ids(repeat) == ["blue_water"], "[renown] a later qualifying voyage pays only the repeatable objective (%s)" % [_ids(repeat)])
	var lifetime := progress.lifetime_renown
	progress.unpublished_renown = 0
	t.check_eq(progress.lifetime_renown, lifetime, "[renown] lifetime renown does not depend on the unpublished balance")


# --- Rescue -----------------------------------------------------------------------------------

func _test_rescue() -> void:
	_new_game()
	GameSession.plan_route_to(&"helsinki")
	GameSession.depart()
	Simulation.advance(22.0 * HOUR)
	t.check(GameSession.get_voyage_sailed_nm() > 100.0, "(setup) more than 100 nm sailed (%.0f)" % GameSession.get_voyage_sailed_nm())
	GameSession.set_condition_for_testing(1.0)
	WeatherFixtures.use([WeatherFixtures.gale("fx_obj", GameSession.get_vessel_position(), 80.0, 52.0,
		GameSession.get_game_time() - HOUR, 96.0, 0.0, 0.0, 250.0)])
	var result := Simulation.advance(6.0 * HOUR)
	t.check(result.rescued, "(setup) the boat is lost")
	var progress := GameSession.get_objective_progress()
	t.check(progress.is_completed(&"distance_100") and not progress.is_completed(&"first_voyage") and not progress.is_completed(&"new_harbour")
		and not progress.is_completed(&"heavy_weather") and not progress.is_completed(&"passage_200"),
		"[renown] a lost voyage: its miles count (100 nm), but no voyage, harbour, passage or weather reward (%s)" % [progress.completed.keys()])
	t.check_eq(GameSession.get_lifetime_renown(), 25, "[renown] 25 renown; the rescue costs money, never renown")
	Simulation.advance(12.0 * HOUR)
	t.check_eq(GameSession.get_lifetime_renown(), 25, "[renown] nothing more is paid after the rescue")
	WeatherFixtures.use([])


# --- Weather ------------------------------------------------------------------------------------

func _test_weather_arrival() -> void:
	_new_game()
	GameSession.plan_route_to(&"kiel")
	GameSession.depart()
	Simulation.advance(2.0 * HOUR)
	WeatherFixtures.use([WeatherFixtures.gale("fx_weather", GameSession.get_vessel_position(), 30.0, 42.0,
		GameSession.get_game_time() - HOUR, 96.0, 0.0, 0.0, 250.0)])
	Simulation.advance(4.0 * HOUR)
	WeatherFixtures.use([])
	_finish_voyage()
	var record: Dictionary = GameSession.get_captains_log().voyages[0]
	var progress := GameSession.get_objective_progress()
	t.check(int(record.worst_hazard) >= WeatherModel.HAZARD_DANGEROUS and float(record.damage) > 0.0,
		"(setup) the passage met dangerous weather and took %.1f %% damage" % float(record.damage))
	t.check(progress.is_completed(&"heavy_weather") and not progress.is_completed(&"clean_150"),
		"[objectives] arriving after the gale completes 'Heavy weather'; a damaged passage is not 'Not a scratch'")


# --- Save and load ------------------------------------------------------------------------------

func _test_persistence() -> void:
	_new_game()
	GameSession.plan_route_to(&"kiel")
	GameSession.depart()
	Simulation.advance(10.0 * HOUR)
	SaveManager.save_to_slot(2, GameSession.get_state_snapshot())
	_finish_voyage()
	var straight := GameSession.get_objective_progress().to_dict()
	var loaded := SaveManager.load_from_slot(2)
	t.check(loaded.is_ok(), "[renown] the save under way loads (%s)" % loaded.error)
	awarded.clear()
	GameSession.replace_state(loaded.state)
	t.check(awarded.is_empty() and GameSession.get_lifetime_renown() == 0, "[renown] loading pays nothing")
	_finish_voyage()
	t.check_eq(GameSession.get_objective_progress().to_dict(), straight, "[renown] continuing after loading pays exactly the same")
	# The arrived game, saved and loaded twice: no second payment.
	SaveManager.save_to_slot(2, GameSession.get_state_snapshot())
	for i in 2:
		awarded.clear()
		var again := SaveManager.load_from_slot(2)
		t.check_eq(again.state.progress.to_dict(), straight, "[renown] renown and objectives are saved and loaded exactly (%d)" % (i + 1))
		GameSession.replace_state(again.state)
		Simulation.advance(6.0 * HOUR)
		t.check(awarded.is_empty() and GameSession.get_lifetime_renown() == 100, "[renown] no repeat payment after loading (%d)" % (i + 1))
	var data := GameSession.get_state_snapshot().to_dict()
	data.progress.unpublished_renown = 500
	var errors: Array[String] = []
	t.check(SessionState.from_dict(data, errors) == null, "[renown] more unpublished than lifetime renown is rejected (%s)" % [errors])
	SaveManager.delete_slot(2)


# --- Migration ------------------------------------------------------------------------------------

func _test_migration() -> void:
	# A version 8 save (Captain's Log, no renown) after a voyage to Kiel.
	_new_game()
	_sail_to(&"kiel")
	var v8: Dictionary = GameSession.get_state_snapshot().to_dict()
	v8.erase("progress")
	var wrapper := {"format": "next_harbor_save", "version": 8, "game_version": "0.6.0",
		"saved_at_unix": 1790000000.0, "saved_at_utc": "2026-09-21T12:53:20Z", "session": v8}
	DirAccess.make_dir_recursive_absolute(SaveManager.save_dir)
	var file := FileAccess.open(SaveManager.save_dir.path_join("slot_3.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(wrapper, "", true, true))
	file.close()
	var migrated := SaveManager.load_from_slot(3)
	t.check(migrated.is_ok(), "[migration] a version 8 save loads (%s)" % migrated.error)
	if not migrated.is_ok():
		return
	t.check(migrated.state.progress.lifetime_renown == 0 and migrated.state.progress.completed.is_empty()
		and migrated.state.captains_log.voyages_completed == 1, "[migration] no renown is paid for the past; the log is kept")
	awarded.clear()
	GameSession.replace_state(migrated.state)
	t.check(awarded.is_empty(), "[migration] loading pays nothing")
	_sail_to(&"copenhagen")
	var ids := _ids(awarded[0]) if awarded.size() == 1 else []
	t.check(ids.has("first_voyage") and ids.has("distance_100") and not ids.has("new_harbour"),
		"[migration] the next voyage's end checks the objectives against the log (%s)" % [ids])
	SaveManager.delete_slot(3)


# --- The Objectives view ---------------------------------------------------------------------------

func _test_objectives_view() -> void:
	WeatherFixtures.use([])
	_sail_to(&"kiel")
	await _settle()
	var messages := Array(app.toasts.get_messages())
	t.check(messages.any(func(m: String) -> bool: return m.begins_with("+100 renown:") and m.contains("Cast off")),
		"[renown ui] one short message for the renown earned (%s)" % [messages])
	for panel in app.toasts.get_children():
		app.toasts.remove_child(panel)
		panel.queue_free()
	var menu := app.open_captains_log() as CaptainsLogMenu
	await t.frames(3)
	t.check((menu.find_child("RenownValue", true, false) as Label).text == "100  (100 unpublished)", "[renown ui] the log shows lifetime and unpublished renown")
	menu.show_tab(CaptainsLogMenu.TAB_OBJECTIVES)
	await t.frames(2)
	t.check_eq(menu.get_current_tab_name(), "Objectives", "[objectives ui] the Objectives tab")
	t.check((menu.find_child("RenownSummary", true, false) as Label).text.contains("100 earned in all, 100 not yet published"),
		"[objectives ui] renown at the top")
	# I024: 'Harbour hopper' (5) is retired as a goal; 'Well travelled' (10) remains.
	t.check(menu.find_child("Objective_harbours_5", true, false) == null, "[objectives ui] a goal retired from the collection is no longer offered")
	var harbours: Control = menu.find_child("Objective_harbours_10", true, false)
	t.check(harbours != null and (harbours.get_node("Detail") as Label).text.contains("Progress: 2 of 10.")
		and (harbours.get_node("Title") as Label).text.contains("50 renown"), "[objectives ui] open objective: requirement, progress and reward")
	var repeat: Control = menu.find_child("Objective_new_harbour", true, false)
	t.check(repeat != null and (repeat.get_node("Title") as Label).text.contains("repeatable")
		and (repeat.get_node("Detail") as Label).text.contains("Completed 1 time"), "[objectives ui] a repeatable objective shows how often it was completed")
	t.check(menu.find_child("Objective_first_voyage", true, false) == null and menu.find_child("Done_first_voyage", true, false) != null,
		"[objectives ui] a completed one-time objective moves to 'Completed'")
	await t.screenshot("110_objectives")
	var scroll: ScrollContainer = menu.find_child("Objectives", true, false)
	scroll.scroll_vertical = 100000
	await t.frames(3)
	await t.screenshot("111_objectives_completed")
	app.modals.clear()
	await t.frames(2)
