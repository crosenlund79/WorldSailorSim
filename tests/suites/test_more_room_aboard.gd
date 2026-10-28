extends RefCounted
## I025, A Little More Room Aboard:
##   - a new game starts without a companion; nothing assumes one (cabin,
##     deck, sleep, departure, the laptop, saving and loading);
##   - older saves keep their companion exactly (the pre-I024 fixture, and a
##     save written by I024), with no adoption date invented;
##   - now and then an animal waits on the dock in a small open box: rare but
##     found (the chance grows with every harbour arrival without one),
##     decided once per arrival, never re-rolled by loading, gone when the
##     boat casts off, none while two companions live aboard;
##   - a few kind gestures and it follows; at the companionway: Adopt (name,
##     gender, welcome aboard) or Not now (a little girl comes to fetch it,
##     for every kind; the conure lands on her shoulder);
##   - the welcome home plays once; two companions (any kinds, the same kind
##     twice, the same name twice) each keep their own identity, places and
##     save; they rest side by side, never on top of one another, wake
##     together with one line, go ashore together and are both called back;
##   - pair moments, pair lines on long passages, the laptop's history, the
##     "Welcome aboard" record (no renown), English and Danish.

const APP_SCENE := preload("res://src/app/app.tscn")

var t: Node
var app: Node


func run(runner: Node) -> void:
	t = runner
	Simulation.auto_advance = false
	WeatherFixtures.use([])
	_test_zero_companions_state()
	_test_old_saves()
	_test_encounter_odds()
	_test_adoption_state()
	_test_saving_mid_encounter()
	_test_remarks()
	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	await _test_new_game_alone()
	for kind in CompanionState.KINDS:
		await _test_encounter_scene(kind)
	await _test_adopt_at_the_companionway()
	for kind in CompanionState.KINDS:
		await _test_not_now(kind)
	await _test_two_companions()
	await _test_two_ashore()
	await _test_laptop_history()
	Engine.time_scale = 1.0
	SettingsManager.set_language(&"en")
	Simulation.auto_advance = true
	app.queue_free()
	await t.frames(2)
	GameSession.end_session()


func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)


func _show(area: StringName, spawn: StringName) -> BoatArea:
	app.modals.clear()
	GameSession.enter_boat_area(area, spawn)
	app._show_current_boat_area()
	await _settle()
	return app.router.current_screen as BoatArea


## Rendered runs only: `count` frames `interval` seconds apart (a motion
## capture, joined into a strip by tools/qa/film_strip.py).
func _film(file_name: String, count: int, interval: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for i in count:
		await t.screenshot("%s_%02d" % [file_name, i])
		await t.get_tree().create_timer(interval).timeout


func _round_trip(state: SessionState) -> SessionState:
	var errors: Array[String] = []
	var data: Variant = JSON.parse_string(JSON.stringify(state.to_dict()))
	return SessionState.from_dict(data, errors)


## A session with `companions` (kinds) already aboard, the Captain moored.
func _session_with(kinds: Array, names: Array = []) -> void:
	GameSession.start_new_session(&"")
	for i in kinds.size():
		GameSession.test_place_dock_animal(kinds[i])
		for step in DockEncounters.TRUST_NEEDED:
			GameSession.befriend_dock_animal()
		GameSession.adopt_dock_animal(String(names[i]) if i < names.size() else "", &"")
		GameSession.mark_companion_welcomed(GameSession.get_companions()[i].id)


# --- State ---------------------------------------------------------------------------

func _test_zero_companions_state() -> void:
	GameSession.start_new_session(&"")
	t.check(GameSession.get_companion() == null and GameSession.get_companion_count() == 0 and GameSession.has_room_for_companion(),
		"[alone] a new game: no companion, room for two")
	t.check(not GameSession.is_companion_ashore() and GameSession.get_companions_ashore().is_empty() and GameSession.companion_departure_refusal() == "",
		"[alone] nobody ashore, nothing holds the boat")
	t.check_eq(GameSession.wake_companion(8.0 * 3600.0), "", "[alone] waking: no companion line")
	var data := GameSession.get_state_snapshot().to_dict()
	t.check((data.companions as Array).is_empty() and not data.has("companion"), "[alone] saved as an empty list, no companion field")
	var loaded := _round_trip(GameSession.get_state_snapshot())
	t.check(loaded != null and loaded.companions.is_empty(), "[alone] loads alone (no companion appears)")


func _test_old_saves() -> void:
	# The real pre-I024 save (a dog without a name).
	var fixture := FileAccess.get_file_as_string("res://tests/fixtures/save_pre_i024.json")
	SaveManager.save_dir = "user://test_saves"
	DirAccess.make_dir_recursive_absolute(SaveManager.save_dir)
	var file := FileAccess.open(SaveManager.save_dir.path_join("slot_3.json"), FileAccess.WRITE)
	file.store_string(fixture)
	file.close()
	var loaded := SaveManager.load_from_slot(3)
	if t.check(loaded.is_ok(), "[old saves] the pre-I024 save loads"):
		var state := loaded.state
		t.check(state.companions.size() == 1 and state.companion.kind == CompanionState.KIND_DOG and state.companion.id == 1,
			"[old saves] its one companion is kept (the dog, id 1)")
		t.check(not state.companion.has_adoption_record() and state.companion.welcomed and state.companion.origin == CompanionState.ORIGIN_START,
			"[old saves] no adoption date or place invented, no welcome replayed")
	# An I024 save: one companion in the old single field, named and gendered.
	var i024 := SessionState.create_new(GameSession.START_LOCATION, GameSession.START_AREA, GameSession.START_SPAWN,
		CompanionState.KIND_PARROT, Difficulty.STANDARD, "Kiwi", CompanionState.GENDER_FEMALE)
	var old: Dictionary = JSON.parse_string(JSON.stringify(i024.to_dict()))
	old.erase("companions")
	old.erase("next_companion_id")
	old.erase("encounters")
	var errors: Array[String] = []
	var state := SessionState.from_dict(old, errors)
	t.check(errors.is_empty() and state.companions.size() == 1 and state.companion.name == "Kiwi" and state.companion.gender == CompanionState.GENDER_FEMALE
		and state.companion.kind == CompanionState.KIND_PARROT, "[old saves] an I024 save keeps Kiwi, her kind, name and gender")
	t.check(state.encounters.current.is_empty() and state.next_companion_id == 2, "[old saves] no animal waiting; the next id follows on")
	# Written again: the old field is still there for the first companion.
	var again := state.to_dict()
	t.check(again.has("companion") and (again.companion as Dictionary).kind == "parrot" and (again.companions as Array).size() == 1,
		"[saves] the first companion is also written to the old field")
	t.check_eq(SaveManager.SAVE_VERSION, 12, "[saves] the save format stays 12 (new fields are optional)")


func _test_encounter_odds() -> void:
	t.check(DockEncounters.chance(0) < DockEncounters.chance(3) and DockEncounters.chance(100) == DockEncounters.CHANCE_MAX,
		"[odds] the chance grows with every arrival without one, up to a cap")
	t.check(DockEncounters.rolls(7, &"kiel", 1234.0, 2) == DockEncounters.rolls(7, &"kiel", 1234.0, 2),
		"[odds] an arrival always gives the same answer (no re-roll by loading)")
	# Many careers: how many arrivals between encounters.
	var gaps: Array[int] = []
	var ports: Array[StringName] = [&"kiel", &"copenhagen", &"helsingor", &"gothenburg", &"oslo", &"lisbon"]
	for career in 40:
		var since := 0
		for arrival in 60:
			var port := ports[(arrival * 7 + career) % ports.size()]
			if DockEncounters.rolls(career * 31 + 5, port, 3600.0 * (arrival * 37 + 11), since):
				gaps.append(since + 1)
				since = 0
			else:
				since += 1
	var total := 0
	var longest := 0
	for gap in gaps:
		total += gap
		longest = maxi(longest, gap)
	var mean := float(total) / maxf(gaps.size(), 1.0)
	t.check(mean >= 3.0 and mean <= 7.0 and longest <= 16, "[odds] rare but found: one in about %.1f arrivals, at most %d apart" % [mean, longest])
	var kinds := {}
	for i in 60:
		kinds[DockEncounters.pick_kind(i, &"kiel", i * 100.0)] = true
	t.check_eq(kinds.size(), 3, "[odds] a cat, a Pug or a conure")
	var garbage := DockEncounters.from_dict({"arrivals_since": "x", "current": {"kind": "wolf", "port": "kiel", "since": 1.0}, "recent": [3, "a:1"]})
	t.check(garbage.arrivals_since == 0 and garbage.current.is_empty() and garbage.recent == ["a:1"], "[odds] damaged data: safe defaults")


func _test_adoption_state() -> void:
	GameSession.start_new_session(&"")
	var renown := GameSession.get_objective_progress().lifetime_renown
	GameSession.test_place_dock_animal(CompanionState.KIND_DOG)
	var encounter := GameSession.get_dock_encounter()
	t.check(encounter.kind == CompanionState.KIND_DOG and encounter.state == DockEncounters.STATE_WAITING, "[adoption] a Pug waits on the dock")
	var steps: Array = []
	for i in DockEncounters.TRUST_NEEDED:
		steps.append(GameSession.befriend_dock_animal())
	t.check(not bool(steps[0].trusting) and bool(steps[-1].trusting) and GameSession.get_dock_encounter().state == DockEncounters.STATE_FOLLOWING,
		"[trust] after %d kind gestures it follows" % DockEncounters.TRUST_NEEDED)
	var biscuit := GameSession.adopt_dock_animal("Biscuit", CompanionState.GENDER_MALE)
	var port := String(GameSession.get_location_id())
	t.check(biscuit != null and biscuit.name == "Biscuit" and biscuit.kind == CompanionState.KIND_DOG and biscuit.gender == CompanionState.GENDER_MALE
		and biscuit.origin == CompanionState.ORIGIN_ADOPTED and biscuit.adopted_port == port and biscuit.adopted_at == GameSession.get_state_snapshot().game_time
		and not biscuit.welcomed and biscuit.area == CompanionState.AREA_CABIN, "[adoption] Biscuit is aboard: kind, name, gender, when and where")
	t.check(GameSession.get_dock_encounter().is_empty() and GameSession.get_companion_count() == 1, "[adoption] the dock is empty again")
	var progress := GameSession.get_objective_progress()
	t.check(progress.is_completed(&"companion:adopted") and progress.lifetime_renown == renown, "[renown] 'Welcome aboard' is recorded, no renown paid")
	# A second one: the same kind and the same name.
	GameSession.test_place_dock_animal(CompanionState.KIND_DOG)
	for i in DockEncounters.TRUST_NEEDED:
		GameSession.befriend_dock_animal()
	var twin := GameSession.adopt_dock_animal("Biscuit", &"")
	var all := GameSession.get_companions()
	t.check(twin != null and all.size() == 2 and all[0].id != all[1].id and all[0].name == all[1].name and all[1].kind == CompanionState.KIND_DOG,
		"[two] a second Pug, also called Biscuit: two companions, two ids")
	GameSession.test_place_dock_animal(CompanionState.KIND_CAT)
	t.check(GameSession.get_dock_encounter().is_empty() and not GameSession.has_room_for_companion() and GameSession.adopt_dock_animal("X", &"") == null,
		"[two] with two aboard no animal waits and no third is taken")
	var loaded := _round_trip(GameSession.get_state_snapshot())
	t.check(loaded.companions.size() == 2 and loaded.companions[0].id == all[0].id and loaded.companions[1].id == all[1].id
		and loaded.companions[1].adopted_port == port and loaded.companions[1].has_adoption_record() and loaded.next_companion_id == 3,
		"[saves] both load as they were (ids, adoption records)")
	t.check_eq(GameSession.get_objective_progress().lifetime_renown, renown, "[renown] petting, gestures and adoptions pay nothing")


func _test_saving_mid_encounter() -> void:
	GameSession.start_new_session(&"")
	GameSession.test_place_dock_animal(CompanionState.KIND_CAT)
	for i in DockEncounters.TRUST_NEEDED:
		GameSession.befriend_dock_animal()
	var loaded := _round_trip(GameSession.get_state_snapshot())
	t.check(loaded.encounters.current.kind == CompanionState.KIND_CAT and loaded.encounters.current.state == DockEncounters.STATE_WAITING
		and int(loaded.encounters.current.trust) == DockEncounters.TRUST_NEEDED, "[saves] saved while it follows: it waits by its box, still trusting")
	# Casting off leaves it on its dock; loading never brings it back.
	GameSession.plan_route_to(&"kiel")
	t.check_eq(GameSession.depart(), "", "(setup) cast off")
	t.check(GameSession.get_dock_encounter().is_empty() and GameSession.get_state_snapshot().encounters.current.is_empty()
		and GameSession.get_state_snapshot().encounters.recent.size() == 1, "[departure] it stays on its dock; the encounter is over")
	t.check(_round_trip(GameSession.get_state_snapshot()).encounters.current.is_empty(), "[saves] and it does not come back on loading")
	# Declining.
	GameSession.start_new_session(&"")
	GameSession.test_place_dock_animal(CompanionState.KIND_PARROT)
	GameSession.decline_dock_animal()
	var state := GameSession.get_state_snapshot()
	t.check(state.encounters.current.is_empty() and state.encounters.declined == 1 and state.companions.is_empty(), "[not now] recorded, nobody aboard, no penalty")


func _test_remarks() -> void:
	var cat := {"kind": CompanionState.KIND_CAT, "name": "Snowy", "gender": &""}
	var dog := {"kind": CompanionState.KIND_DOG, "name": "Fido", "gender": &""}
	var parrot := {"kind": CompanionState.KIND_PARROT, "name": "Kiwi", "gender": &""}
	var both := CompanionRemarks.still_ashore_all([cat, dog] as Array[Dictionary])
	t.check(both.contains("Snowy") and both.contains("Fido"), "[two ashore] '%s'" % both)
	var lines := {}
	for day in 8:
		var line := CompanionRemarks.wake_line_all([cat, dog] as Array[Dictionary], day)
		if line != "":
			lines[line] = true
	t.check(lines.size() >= 1 and lines.keys().all(func(l: String) -> bool: return l.contains("Snowy") and l.contains("Fido")),
		"[waking] one line for both: %s" % lines.keys().slice(0, 1))
	var pair := CompanionRemarks.passage_pair_lines(parrot, dog, 2)
	t.check(not pair.is_empty(), "[passage] the Captain has lines for the pair: '%s'" % (CompanionRemarks.say_pair(parrot, dog, pair[0]) if not pair.is_empty() else ""))
	for kind in CompanionState.KINDS:
		t.check(CompanionRemarks.followed_home(kind).ends_with("?") and CompanionRemarks.befriend_line(kind, DockEncounters.TRUST_NEEDED) != "",
			"[words] %s: the question and the gestures" % kind)
	SettingsManager.set_language(&"da")
	var danish := [CompanionRemarks.followed_home(CompanionState.KIND_DOG), CompanionRemarks.befriend_line(CompanionState.KIND_CAT, 1),
		CompanionRemarks.still_ashore_all([cat, dog] as Array[Dictionary]), CompanionRemarks.befriend_prompt(CompanionState.KIND_PARROT, 0)]
	SettingsManager.set_language(&"en")
	var english := [CompanionRemarks.followed_home(CompanionState.KIND_DOG), CompanionRemarks.befriend_line(CompanionState.KIND_CAT, 1),
		CompanionRemarks.still_ashore_all([cat, dog] as Array[Dictionary]), CompanionRemarks.befriend_prompt(CompanionState.KIND_PARROT, 0)]
	for i in danish.size():
		t.check(danish[i] != english[i], "[danish] '%s'" % danish[i])


# --- In the game ---------------------------------------------------------------------

func _test_new_game_alone() -> void:
	app.start_new_game(&"", Difficulty.STANDARD)
	await _settle()
	var cabin := await _show(SessionState.AREA_INTERIOR, &"from_deck")
	var shown := cabin.get_companion_nodes().filter(func(n: ShipCompanion) -> bool: return n.visible)
	t.check(GameSession.get_companion_count() == 0 and cabin.get_companion_nodes().size() == 2 and shown.is_empty(),
		"[alone] the cabin: no animal shown (both places empty)")
	await t.screenshot("i025_01_captain_alone")
	var deck := await _show(SessionState.AREA_EXTERIOR, &"start")
	t.check(deck.get_companion_nodes().all(func(n: ShipCompanion) -> bool: return not n.visible), "[alone] the deck: nobody")
	app.sleep_for(8.0)
	await _settle()
	t.check(GameSession.get_companion_count() == 0 and not app.toasts.get_messages().has(""), "[alone] a night's sleep without a companion")
	t.check(not app.get_wheel_actions().any(func(a: Dictionary) -> bool: return a.id == &"call_aboard"), "[alone] nobody to call aboard")
	var laptop := app.open_laptop(LaptopView.APP_HISTORY) as LaptopView
	await t.frames(3)
	t.check(laptop != null and laptop.find_child("Companion_0", true, false) == null, "[alone] the laptop's history: no companion rows")
	app.modals.clear()
	await t.frames(2)


func _dock() -> DockEncounterScene:
	var area := app.router.current_screen as BoatArea
	return area.get_dock_encounter_scene() if area else null


func _test_encounter_scene(kind: StringName) -> void:
	GameSession.start_new_session(&"")
	t.set_wind(200.0, 8.0)
	GameSession.test_place_dock_animal(kind)
	var deck := await _show(SessionState.AREA_EXTERIOR, &"start")
	var dock := _dock()
	if not t.check(dock != null and dock.animal != null and dock.kind == kind, "[dock] a %s waits on the pontoon" % kind):
		return
	var shore := deck.get_shore_access()
	var box := dock.get_box_position()
	t.check(shore.is_off_the_boat(box) and absf(box.x - shore.get_plank_x()) > 250.0, "[dock] its box stands on the pontoon, away from the gangplank and services")
	var drawn := Rect2()
	for p in dock.animal.get_local_outline():
		drawn = Rect2(p, Vector2.ZERO) if drawn.size == Vector2.ZERO and drawn.position == Vector2.ZERO else drawn.expand(p)
	t.check(dock.animal.is_sprite_mode() and dock.animal.visible and dock.animal.position.distance_to(box) < 60.0 and absf(drawn.get_center().x) < 30.0,
		"[dock] the %s is drawn at its box (at %s, box %s, drawn %s, facing %d)" % [kind, dock.animal.position.round(), box.round(), drawn, dock.animal.facing])
	if kind == CompanionState.KIND_PARROT:
		t.check(dock.animal.position.is_equal_approx(box + DockBox.RIM), "[dock] the conure perches on the open box's rim")
	deck.player.position = box + Vector2(-70.0 * signf(box.x - shore.get_plank_x()), 6.0)
	await t.physics_frames(3)
	await t.screenshot("i025_encounter_%s" % kind)
	t.check(dock.animal.interactable.enabled and dock.animal.interactable.prompt != "", "[trust] '%s'" % dock.animal.interactable.prompt)
	for i in DockEncounters.TRUST_NEEDED:
		dock._cooldown = 0.0
		var line := dock.befriend()
		t.check(line != "", "[trust] %s, gesture %d: '%s'" % [kind, i + 1, line])
	t.check(dock.is_following() and not dock.animal.interactable.enabled, "[trust] the %s follows the Captain" % kind)
	# It follows the Captain along the pontoon.
	deck.player.position = shore.get_landing_point() + Vector2(0, 20)
	var start := dock.animal.position.distance_to(deck.player.position)
	await t.wait_until(func() -> bool: return dock.animal.position.distance_to(deck.player.position) < DockEncounterScene.FOLLOW_START + 10.0, 30.0)
	t.check(dock.animal.position.distance_to(deck.player.position) < start, "[trust] it comes along (%.0f -> %.0f)" % [start, dock.animal.position.distance_to(deck.player.position)])
	await t.screenshot("i025_following_%s" % kind)


func _test_adopt_at_the_companionway() -> void:
	# Following (from the last test: the conure); the Captain goes below.
	if not t.check(_dock() != null and _dock().is_following(), "(setup) an animal follows"):
		return
	var deck := app.router.current_screen as BoatArea
	app._on_area_change_requested(SessionState.AREA_INTERIOR, &"from_deck")
	await t.frames(3)
	var dialog := app.modals.get_top() as AdoptionDialog
	if not t.check(dialog != null and (dialog.find_child("Text", true, false) as Label).text.contains("followed you all the way home"),
			"[decision] at the companionway: the question"):
		return
	await t.screenshot("i025_05_adoption_decision")
	dialog.handle_back()
	await t.frames(3)
	t.check(app.modals.is_empty() and _dock().is_following() and app.router.current_screen == deck and deck.player.input_enabled,
		"[decision] Esc decides nothing: still on deck, it still follows")
	app._on_area_change_requested(SessionState.AREA_INTERIOR, &"from_deck")
	await t.frames(3)
	dialog = app.modals.get_top() as AdoptionDialog
	dialog.choose_adopt()
	dialog.name_edit.text = "Pippa"
	dialog.gender_picker.select(1)
	await t.frames(2)
	await t.screenshot("i025_adoption_naming")
	await t.click(dialog.find_child("WelcomeButton", true, false) as Button)
	await _settle()
	var cabin := app.router.current_screen as BoatArea
	var pippa := GameSession.get_companion()
	t.check(cabin.area_id == SessionState.AREA_INTERIOR and pippa != null and pippa.name == "Pippa" and pippa.kind == CompanionState.KIND_PARROT
		and pippa.gender == CompanionState.GENDER_FEMALE, "[adoption] below with Pippa, a female conure")
	var node := cabin.get_companion_nodes()[0]
	await t.frames(4)
	t.check(GameSession.get_companion().welcomed, "[welcome] the welcome home starts (and is never played again)")
	await t.wait_until(func() -> bool: return node.is_walking(), 3.0)
	await t.screenshot("i025_06_welcome_conure")
	await _film("film_welcome_conure", 8, 0.6)
	await t.wait_until(func() -> bool: return not node.is_walking(), 15.0)
	await t.frames(30)
	# Again in the cabin: no second welcome.
	await _show(SessionState.AREA_EXTERIOR, &"from_cabin")
	cabin = await _show(SessionState.AREA_INTERIOR, &"from_deck")
	node = cabin.get_companion_nodes()[0]
	await t.frames(4)
	t.check(not node.is_walking() and node.position.is_equal_approx(node._rest_position()), "[welcome] coming below again: it is simply at its place")


func _test_not_now(kind: StringName) -> void:
	GameSession.start_new_session(&"")
	GameSession.test_place_dock_animal(kind)
	for i in DockEncounters.TRUST_NEEDED:
		GameSession.befriend_dock_animal()
	var deck := await _show(SessionState.AREA_EXTERIOR, &"start")
	var dock := _dock()
	if not t.check(dock != null and dock.is_following(), "(setup) a following %s" % kind):
		return
	app._on_area_change_requested(SessionState.AREA_INTERIOR, &"from_deck")
	await t.frames(3)
	var dialog := app.modals.get_top() as AdoptionDialog
	if not t.check(dialog != null, "[not now] the question (%s)" % kind):
		return
	await t.click(dialog.find_child("NotNowButton", true, false) as Button)
	await t.frames(3)
	t.check(app.router.current_screen == deck and dock.is_farewell() and GameSession.get_companion_count() == 0
		and GameSession.get_dock_encounter().is_empty(), "[not now] the Captain stays on deck; the %s goes back to the dock" % kind)
	# Rendered runs play it at its real pace (for the screenshots and the film).
	Engine.time_scale = 4.0 if DisplayServer.get_name() == "headless" else 1.0
	await t.wait_until(func() -> bool: return dock.girl != null, 40.0)
	await _film("film_girl_%s" % kind, 12, 0.8)
	var met: bool = await t.wait_until(func() -> bool: return dock.girl != null and not dock.girl.is_walking() and dock.girl.waving > 0.5, 40.0)
	t.check(met, "[the girl] she comes along the pontoon and waves")
	await t.wait_until(func() -> bool: return dock.animal != null and not dock.animal.is_walking() and dock.animal.position.distance_to(dock.girl.position) < 40.0, 20.0)
	if dock.girl:
		t.check(dock.animal.position.distance_to(dock.girl.position) < 40.0, "[the girl] the %s goes to her (%s, she is at %s, the box at %s)"
			% [kind, dock.animal.position.round(), dock.girl.position.round(), dock.get_box_position().round()])
		if kind == CompanionState.KIND_PARROT:
			t.check(dock.animal.position.distance_to(dock.girl.get_shoulder()) < 6.0, "[the girl] the conure lands on her shoulder")
		await t.screenshot("i025_girl_with_%s" % kind)
	await t.wait_until(func() -> bool: return dock.girl != null and dock.girl.carrying_box and dock.girl.is_walking(), 20.0)
	await t.frames(8)
	await t.screenshot("i025_girl_leaving_%s" % kind)
	var finished: bool = await t.wait_until(func() -> bool: return dock.animal == null and not dock.is_farewell(), 60.0)
	Engine.time_scale = 1.0
	t.check(finished and GameSession.get_dock_encounter().is_empty() and GameSession.get_companion_count() == 0,
		"[the girl] they leave together; the dock is quiet, nobody added")
	t.check(app.toasts.get_messages().size() <= 3, "[the girl] no words, no guilt")


func _test_two_companions() -> void:
	_session_with([CompanionState.KIND_CAT, CompanionState.KIND_DOG], ["Snowy", "Biscuit"])
	var cabin := await _show(SessionState.AREA_INTERIOR, &"from_deck")
	var nodes := cabin.get_companion_nodes()
	t.check(nodes.size() == 2 and nodes[0].visible and nodes[1].visible and nodes[0].kind == CompanionState.KIND_CAT and nodes[1].kind == CompanionState.KIND_DOG,
		"[two] both in the cabin, each its own node")
	await t.screenshot("i025_two_in_cabin")
	# The same spot: side by side, never on top of one another.
	var spot := GameSession.get_companions()[0].spot
	var edited := GameSession.get_state_snapshot()
	edited.companions[1].spot = spot
	edited.companions[1].area = CompanionState.AREA_CABIN
	GameSession.replace_state(edited)
	await t.frames(3)
	t.check(nodes[0].position.distance_to(nodes[1].position) >= 20.0, "[two] sharing '%s': side by side (%.0f apart)" % [spot, nodes[0].position.distance_to(nodes[1].position)])
	await t.screenshot("i025_08_two_resting")
	# Pair moments.
	var moments := cabin.get_pair_moments()
	if t.check(moments != null, "[pair] the cabin has pair moments"):
		await t.wait_until(func() -> bool: return moments.ready_for_moment(), 5.0)
		var played := moments.play_moment("visit_back")
		t.check(played == "visit_back", "[pair] cat and Pug: '%s'" % played)
		await t.wait_until(func() -> bool: return nodes[1].is_walking(), 2.0)
		await _film("film_pair_cat_pug", 8, 0.7)
		await t.wait_until(func() -> bool: return not nodes[1].is_walking(), 15.0)
		await t.frames(10)
		await t.screenshot("i025_07_pair_greeting")
	# Sleep: both by the berth, one line naming both.
	app.toasts.clear()
	app.sleep_for(8.0)
	await _settle()
	var all := GameSession.get_companions()
	cabin = app.router.current_screen as BoatArea
	nodes = cabin.get_companion_nodes()
	t.check(all[0].spot == CompanionState.WAKE_SPOT and all[1].spot == CompanionState.WAKE_SPOT and nodes[0].position.distance_to(nodes[1].position) >= 20.0,
		"[sleep] both by the berth, not in the same place")
	await t.screenshot("i025_two_by_the_berth")


func _test_two_ashore() -> void:
	_session_with([CompanionState.KIND_PARROT, CompanionState.KIND_PARROT], ["Kiwi", "Kiwi"])
	t.set_wind(200.0, 8.0)
	var deck := await _show(SessionState.AREA_EXTERIOR, &"start")
	var shore := deck.get_shore_access()
	deck.player.position = shore.get_landing_point() + Vector2(60, 10)
	await t.physics_frames(3)
	await t.wait_until(func() -> bool: return GameSession.get_companions_ashore().size() == 2, 20.0)
	t.check_eq(GameSession.get_companions_ashore().size(), 2, "[ashore] both conures follow the Captain ashore")
	await t.wait_until(func() -> bool: return deck.get_companion_nodes().all(func(n: ShipCompanion) -> bool: return not n.is_walking()), 20.0)
	var nodes := deck.get_companion_nodes()
	t.check(nodes[0].position.distance_to(nodes[1].position) > 20.0, "[ashore] at different places on the pontoon")
	await t.screenshot("i025_17_two_ashore")
	GameSession.plan_route_to(&"kiel")
	var refusal := GameSession.depart()
	t.check(refusal != "" and not GameSession.is_underway(), "[departure] refused: '%s'" % refusal)
	app.recall_companion()
	await t.frames(3)
	t.check(GameSession.get_companions_ashore().is_empty(), "[departure] 'call aboard' brings both back")
	app.modals.clear()
	t.check_eq(GameSession.depart(), "", "[departure] then the boat can cast off")
	await _settle()


func _test_laptop_history() -> void:
	_session_with([CompanionState.KIND_DOG], ["Biscuit"])
	await _show(SessionState.AREA_INTERIOR, &"from_deck")
	var laptop := app.open_laptop(LaptopView.APP_HISTORY) as LaptopView
	await t.frames(4)
	var row := laptop.find_child("Companion_0", true, false) as Label if laptop else null
	var port := PortCatalog.get_default().get_display_name(GameSession.get_location_id())
	t.check(row != null and row.text.contains("Welcomed Biscuit aboard in %s" % port), "[history] '%s'" % (row.text if row else ""))
	await t.screenshot("i025_laptop_history")
	app.modals.clear()
	await t.frames(2)
