extends RefCounted
## I027 Tier 4, Dreams of the Sea: the journal's dreams (eight, two for
## later); none fulfilled in a new game; up to three pursued in any order,
## the later ones never; a real passage of 100 nm or more fulfils "A passage
## of your own" with a notice; buying an ocean-going yacht fulfils "A boat for
## the oceans"; a loaded game's past fulfils its dreams quietly; the dreams go
## through a save, and an older save without them loads with none; the
## laptop's Dreams app in English and Danish.

const APP_SCENE := preload("res://src/app/app.tscn")
const STEADY := preload("res://tests/suites/test_steady_hands.gd")

var t: Node


func run(runner: Node) -> void:
	t = runner
	Simulation.auto_advance = false
	GameSession.test_all_boats_owned = false
	_test_catalogue()
	_test_pursuing()
	await _test_real_passage()
	_test_ocean_boat()
	_test_quiet_on_load()
	_test_save()
	await _test_laptop()
	GameSession.test_all_boats_owned = true
	Simulation.auto_advance = true
	t.use_calm_wind()
	GameSession.end_session()


func _test_catalogue() -> void:
	var all := Dreams.all()
	var later := all.filter(func(d: Dictionary) -> bool: return not Dreams.is_active(d))
	t.check(all.size() == 8 and later.size() == 2, "[dreams] eight dreams, two of them for later (I028): %d, %d" % [all.size(), later.size()])
	GameSession.start_new_session()
	var fulfilled := all.filter(func(d: Dictionary) -> bool: return GameSession.get_dream_status(StringName(d.id)) == GameSession.DREAM_FULFILLED)
	t.check(fulfilled.is_empty() and GameSession.get_dream_status(&"travel_book") == GameSession.DREAM_LATER
		and GameSession.get_dream_status(&"caribbean") == GameSession.DREAM_OPEN,
		"[dreams] a new game: nothing fulfilled, the Caribbean open, the travel book for later")


func _test_pursuing() -> void:
	GameSession.start_new_session()
	var first := [GameSession.set_dream_pursued(&"caribbean", true), GameSession.set_dream_pursued(&"ocean_crossing", true),
		GameSession.set_dream_pursued(&"northern_coast", true)]
	var fourth := GameSession.set_dream_pursued(&"southern_waters", true)
	t.check(first == ["", "", ""] and fourth != "" and GameSession.get_pursued_dreams().size() == 3,
		"[dreams] up to three pursued, in any order; a fourth is refused ('%s')" % fourth)
	t.check(GameSession.set_dream_pursued(&"world_traveller", true) != "", "[dreams] a dream for later cannot be pursued yet")
	GameSession.set_dream_pursued(&"ocean_crossing", false)
	t.check(GameSession.set_dream_pursued(&"southern_waters", true) == "" and GameSession.get_dream_status(&"ocean_crossing") == GameSession.DREAM_OPEN,
		"[dreams] set one aside and another can be pursued")


## Copenhagen to Kiel (about 150 nm) sailed for real, the wind on the beam.
func _test_real_passage() -> void:
	GameSession.start_new_session()
	GameSession.set_dream_pursued(&"own_passage", true)
	var notices: Array[String] = []
	var listen := func(text: String) -> void: notices.append(text)
	GameSession.notice.connect(listen)
	GameSession.plan_route_to(&"kiel")
	GameSession.depart()
	var guard := 0
	while GameSession.is_underway() and guard < 400:
		var voyage := GameSession.get_voyage()
		t.set_wind(fposmod(voyage.leg_bearing_at(voyage.progress_nm) + 100.0, 360.0), 14.0)
		Simulation.advance(1800.0)
		guard += 1
	await t.frames(2)
	GameSession.notice.disconnect(listen)
	var record := GameSession.get_dream_record(&"own_passage")
	t.check(GameSession.get_dream_status(&"own_passage") == GameSession.DREAM_FULFILLED and String(record.get("port", "")) == "kiel"
		and not &"own_passage" in GameSession.get_pursued_dreams(),
		"[dreams] a real passage of %.0f nm to Kiel: 'A passage of your own' came true there" % GameSession.get_captains_log().get_longest_nm())
	t.check(notices.any(func(n: String) -> bool: return n.contains("A dream come true")), "[dreams] with a notice %s" % [notices])
	t.check(GameSession.get_dream_status(&"ocean_crossing") == GameSession.DREAM_OPEN, "[dreams] and not the ocean crossing (1,000 nm)")
	t.use_calm_wind()


func _test_ocean_boat() -> void:
	GameSession.start_new_session()
	var state := GameSession.get_state_snapshot()
	state.funds = 60000
	GameSession.replace_state(state)
	t.check(GameSession.get_dream_status(&"ocean_boat") == GameSession.DREAM_OPEN, "[dreams] the 26 ft is not fitted for oceans")
	var bought := GameSession.buy_vessel(&"starling_33")
	t.check(bought == "" and GameSession.get_dream_status(&"ocean_boat") == GameSession.DREAM_FULFILLED,
		"[dreams] buying the Wing 33 (fitted for oceans): 'A boat for the oceans' came true (%s)" % bought)


## A game whose log already reaches the far north: fulfilled on load, quietly.
func _test_quiet_on_load() -> void:
	GameSession.start_new_session()
	var state := GameSession.get_state_snapshot()
	for port in ["alesund", "trondheim", "tromso"]:
		state.captains_log.visited[port] = {"first": state.game_time - 86400.0, "arrivals": 1}
	var notices: Array[String] = []
	var listen := func(text: String) -> void: notices.append(text)
	GameSession.notice.connect(listen)
	GameSession.replace_state(state)
	GameSession.notice.disconnect(listen)
	t.check(GameSession.get_dream_status(&"northern_coast") == GameSession.DREAM_FULFILLED and notices.is_empty() and not GameSession.has_unsaved_changes(),
		"[dreams] a loaded game that has been to Ålesund, Trondheim and Tromsø: 'The northern coast' quietly true (%d notices)" % notices.size())


func _test_save() -> void:
	GameSession.start_new_session()
	GameSession.set_dream_pursued(&"caribbean", true)
	var state := GameSession.get_state_snapshot()
	state.dreams.fulfilled["southern_waters"] = {"time": 123.0, "port": "naples", "vessel": "arctic_wanderer_26"}
	var errors: Array[String] = []
	var loaded := SessionState.from_dict(state.to_dict(), errors)
	t.check(loaded != null and loaded.dreams.pursuing == ["caribbean"] and loaded.dreams.fulfilled.has("southern_waters"),
		"[save] the dreams pursued and fulfilled go through a save %s" % [errors])
	var old := state.to_dict()
	old.erase("dreams")
	var older := SessionState.from_dict(old, errors)
	t.check(older != null and older.dreams.pursuing.is_empty() and older.dreams.fulfilled.is_empty(), "[save] an older save loads with no dreams")
	old["dreams"] = {"pursuing": ["nonsense", 5, "caribbean"], "fulfilled": {"nonsense": {}, "caribbean": "x"}}
	var odd := SessionState.from_dict(old, errors)
	t.check(odd != null and odd.dreams.pursuing == ["caribbean"] and odd.dreams.fulfilled.is_empty(), "[save] unknown or malformed dreams are dropped")


func _test_laptop() -> void:
	var app: Node = APP_SCENE.instantiate()
	t.add_child(app)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	app.start_new_game()
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.frames(4)
	for language: StringName in [&"en", &"da"]:
		SettingsManager.set_language(language)
		app.modals.clear()
		var laptop := app.open_laptop(LaptopView.APP_DREAMS) as LaptopView
		await t.frames(3)
		if not t.check(laptop != null, "[laptop %s] the laptop opens on Dreams" % language):
			break
		var content := laptop.get_content()
		var cards := content.find_children("Dream_*", "", true, false)
		var button := content.find_child("Dream_caribbean", true, false).find_child("PursueButton", true, false) as Button
		t.check(cards.size() == 8 and button != null, "[laptop %s] eight dreams, each with its card" % language)
		if language == &"en" and button:
			await t.click(button)
			await t.frames(2)
			var status := laptop.get_content().find_child("Dream_caribbean", true, false).find_child("Status", true, false) as Label
			t.check(GameSession.get_dream_status(&"caribbean") == GameSession.DREAM_PURSUING and status.text.begins_with("Pursuing"),
				"[laptop] Pursue this dream: the Caribbean is pursued ('%s')" % status.text)
		if language == &"da":
			var english: Array[String] = []
			for label in laptop.get_content().find_children("*", "Label", true, false):
				var phrase := STEADY.english_phrase((label as Label).text)
				if not phrase.is_empty():
					english.append(phrase)
			t.check(english.is_empty(), "[laptop da] Dreams in Danish %s" % [english])
		await t.screenshot("i027_dreams_%s" % language)
	SettingsManager.set_language(&"en")
	app.modals.clear()
	app.queue_free()
	await t.frames(2)
