extends RefCounted
## I022, The Captain's Other Life: boats with prices (bought once, kept for
## good, never below zero money, old saves keep every boat), the three
## difficulty levels (what they change, saves, changing during a game), and
## the new game and pause menus that offer them; the pastimes aboard
## (Postcards from the Sea, A Game Developer at Sea) on the one clock.

const APP_SCENE := preload("res://src/app/app.tscn")

var t: Node
var app: Node


func run(runner: Node) -> void:
	t = runner
	_test_prices_and_new_games()
	_test_old_saves()
	_test_buying()
	_test_difficulty_factors()
	_test_postcards()
	_test_game_dev()
	_test_pastime_saves()
	Simulation.auto_advance = false
	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	await _test_menus()
	await _test_pastimes_on_the_clock()
	await _test_pastime_menus()
	app.queue_free()
	await t.frames(2)
	GameSession.test_all_boats_owned = true
	Simulation.auto_advance = true  # as the other suites leave it


func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)


func _moor_in(port_id: StringName) -> void:
	var state := GameSession.get_state_snapshot()
	state.location_id = port_id
	state.vessel_status = SessionState.STATUS_MOORED
	state.vessel_position = PortCatalog.get_default().get_port(port_id).get_geo_position()
	state.voyage = null
	GameSession.replace_state(state)


func _round_trip() -> SessionState:
	var errors: Array[String] = []
	var data: Dictionary = JSON.parse_string(JSON.stringify(GameSession.get_state_snapshot().to_dict()))
	return SessionState.from_dict(data, errors)


# --- Boats and prices ------------------------------------------------------------------------------

func _test_prices_and_new_games() -> void:
	var catalog := VesselCatalog.get_default()
	var priced := catalog.vessels.all(func(v: VesselDefinition) -> bool: return v.price > 0)
	var starter := catalog.get_starter()
	var others := catalog.vessels.filter(func(v: VesselDefinition) -> bool: return v.id != starter.id)
	t.check(priced and others.all(func(v: VesselDefinition) -> bool: return v.price > starter.price),
		"[boats] every boat has a price, the starter the lowest (%s)" % [catalog.vessels.map(func(v: VesselDefinition) -> String: return "%s %d" % [v.id, v.price])])
	for level in Difficulty.LEVELS:
		GameSession.start_new_session(CompanionState.DEFAULT_KIND, level)
		t.check(GameSession.get_owned_vessels() == ([starter.id] as Array[StringName]) and GameSession.get_vessel_id() == starter.id
			and GameSession.get_funds() == Difficulty.starting_funds(level) and GameSession.get_difficulty() == level,
			"[new game] %s: aboard the starter, which is yours, with %s" % [level, GameSession.format_money(GameSession.get_funds())])
	t.check(Difficulty.starting_funds(Difficulty.RELAXED) > Difficulty.starting_funds(Difficulty.STANDARD)
		and Difficulty.starting_funds(Difficulty.STANDARD) == SessionState.STARTING_FUNDS
		and Difficulty.starting_funds(Difficulty.SEASONED) < Difficulty.starting_funds(Difficulty.STANDARD), "[new game] more money when relaxed, less when seasoned")
	GameSession.start_new_session(CompanionState.DEFAULT_KIND, Difficulty.SEASONED)
	var back := _round_trip()
	t.check(back != null and back.difficulty == Difficulty.SEASONED and back.owned_vessels == ([starter.id] as Array[StringName]),
		"[saves] the difficulty and the owned boats are saved")


func _test_old_saves() -> void:
	GameSession.start_new_session()
	var data: Dictionary = JSON.parse_string(JSON.stringify(GameSession.get_state_snapshot().to_dict()))
	data.erase("fleet")
	data.erase("difficulty")
	data.vessel.id = "petrel_36"
	var errors: Array[String] = []
	var old := SessionState.from_dict(data, errors)
	t.check(old != null and errors.is_empty() and old.difficulty == Difficulty.STANDARD
		and old.owned_vessels.size() == VesselCatalog.get_default().vessels.size() and old.funds == GameSession.get_funds(),
		"[old saves] a save from before I022: every boat stays yours (they were all free to sail), Standard, the money unchanged (%s)" % [errors])
	var odd: Dictionary = data.duplicate(true)
	odd["fleet"] = {"owned": ["gold_yacht", 7, "starling_33"]}
	odd["difficulty"] = "nightmare"
	var tolerant := SessionState.from_dict(odd, errors)
	t.check(tolerant != null and tolerant.difficulty == Difficulty.STANDARD and tolerant.owned_vessels == ([&"starling_33", &"petrel_36"] as Array[StringName]),
		"[saves] unknown boats and levels are dropped; the boat aboard is always yours (%s)" % [tolerant.owned_vessels if tolerant else []])


func _test_buying() -> void:
	GameSession.test_all_boats_owned = false
	GameSession.start_new_session()
	_moor_in(&"copenhagen")
	var wing := VesselCatalog.get_default().get_vessel(&"starling_33")
	var funds := GameSession.get_funds()
	t.check(GameSession.switch_vessel(&"starling_33") != "" and GameSession.get_vessel_id() == VesselCatalog.STARTER_ID,
		"[buying] a boat that is not yours cannot be sailed away")
	t.check(GameSession.buy_vessel(&"starling_33") != "" and GameSession.get_funds() == funds and not GameSession.owns_vessel(&"starling_33"),
		"[buying] not enough money: refused, the money untouched (%s for %s)" % [GameSession.format_money(funds), GameSession.format_money(wing.price)])
	var state := GameSession.get_state_snapshot()
	state.funds = wing.price + 500
	GameSession.replace_state(state)
	var bought := []
	GameSession.fleet_changed.connect(func() -> void: bought.append(true), CONNECT_ONE_SHOT)
	t.check(GameSession.buy_vessel(&"starling_33") == "" and GameSession.get_funds() == 500 and GameSession.owns_vessel(&"starling_33")
		and not bought.is_empty(), "[buying] bought for %s: 500 left, the Wing 33 is yours" % GameSession.format_money(wing.price))
	t.check(GameSession.buy_vessel(&"starling_33") != "" and GameSession.get_funds() == 500, "[buying] never twice")
	t.check(GameSession.switch_vessel(&"starling_33") == "" and GameSession.get_vessel_id() == &"starling_33"
		and GameSession.switch_vessel(VesselCatalog.STARTER_ID) == "", "[buying] move aboard it, and back to the first boat (still yours, free)")
	var back := _round_trip()
	t.check(back != null and back.owned_vessels.has(&"starling_33") and back.owned_vessels.has(VesselCatalog.STARTER_ID) and back.funds == 500,
		"[saves] the bought boat stays yours after saving and loading")
	GameSession.plan_route_to(&"helsingor")
	GameSession.depart()
	state = GameSession.get_state_snapshot()
	state.funds = 99999
	GameSession.replace_state(state)
	t.check(GameSession.buy_vessel(&"halcyon_40") != "" and not GameSession.owns_vessel(&"halcyon_40"), "[buying] only at a boatyard in harbour")
	GameSession.test_all_boats_owned = true


# --- Difficulty -------------------------------------------------------------------------------------

func _test_difficulty_factors() -> void:
	var results := {}
	for level in Difficulty.LEVELS:
		GameSession.start_new_session(CompanionState.DEFAULT_KIND, level)
		_moor_in(&"copenhagen")
		var before := GameSession.get_provisions().food_days
		Simulation.advance(86400.0)
		var eaten := before - GameSession.get_provisions().food_days
		results[level] = {"eaten": eaten, "price": GameSession.get_provisions_price(), "repair": int(GameSession.service_quote(BoatCare.SERVICE_ENGINE).cost)}
	var s: Dictionary = results[Difficulty.STANDARD]
	var r: Dictionary = results[Difficulty.RELAXED]
	var h: Dictionary = results[Difficulty.SEASONED]
	t.check(absf(s.eaten - 1.0) < 1e-6, "[difficulty] Standard: one day's food a day, as before (%.3f)" % s.eaten)
	t.check(r.eaten < s.eaten and h.eaten > s.eaten, "[difficulty] food lasts longer when relaxed, shorter when seasoned (%.2f / %.2f / %.2f)" % [r.eaten, s.eaten, h.eaten])
	t.check(r.repair < s.repair and h.repair > s.repair and r.price < s.price and h.price > s.price,
		"[difficulty] boat care and provisions cost less when relaxed, more when seasoned (engine service %d / %d / %d)" % [r.repair, s.repair, h.repair])
	t.check(Difficulty.value_of(Difficulty.STANDARD, "wear") == 1.0 and Difficulty.value_of(Difficulty.SEASONED, "wear") > 1.0
		and Difficulty.value_of(Difficulty.RELAXED, "weather_damage") < 1.0, "[difficulty] wear and weather damage scale; the weather itself is the same")
	# Changing during a game: from now on, nothing taken back.
	GameSession.start_new_session()
	var funds := GameSession.get_funds()
	var heard := []
	GameSession.difficulty_changed.connect(func(level: StringName) -> void: heard.append(level), CONNECT_ONE_SHOT)
	GameSession.set_difficulty(Difficulty.RELAXED)
	t.check(GameSession.get_difficulty() == Difficulty.RELAXED and GameSession.get_funds() == funds and heard == [Difficulty.RELAXED],
		"[difficulty] changed during a game: it counts from now on, the money stays as it was")
	SettingsManager.set_language(&"da")
	var names := Difficulty.LEVELS.map(func(level: StringName) -> String: return Difficulty.display_name(level))
	var texts := Difficulty.LEVELS.all(func(level: StringName) -> bool: return Difficulty.describe(level) != "" and Loc.t(Difficulty.describe(level)) == Difficulty.describe(level))
	SettingsManager.set_language(&"en")
	t.check(names == ["Afslappet", "Standard", "Erfaren skipper"] and texts, "[dansk] %s" % [names])


# --- Pastimes -------------------------------------------------------------------------------------

func _test_postcards() -> void:
	GameSession.start_new_session()
	_moor_in(&"copenhagen")
	var subjects := Pastimes.subjects()
	t.check(subjects.any(func(s: Dictionary) -> bool: return s.kind == "companion") and Pastimes.postcard_minutes() == 120.0,
		"[postcards] real subjects from the game (%s); a card takes 2 hours" % [subjects.map(func(s: Dictionary) -> String: return "%s:%s" % [s.kind, s.subject])])
	var companion: Dictionary = subjects.filter(func(s: Dictionary) -> bool: return s.kind == "companion")[0]
	var renown := GameSession.get_unpublished_renown()
	GameSession.set_postcard_draft(companion.kind, companion.subject, 1, "snapshot")
	var half := GameSession.work_on_postcard(45.0)
	t.check(not half.done and GameSession.postcard_minutes_left() == 75.0 and GameSession.get_pastimes().postcards.is_empty(),
		"[postcards] interrupted after 45 min: the card is kept, 75 min left")
	GameSession.set_postcard_draft(companion.kind, companion.subject, 2, "banner")
	t.check(GameSession.postcard_minutes_left() == 75.0, "[postcards] changing the words of the same card keeps the time already given it")
	var done := GameSession.work_on_postcard(75.0)
	t.check(done.done and GameSession.get_pastimes().draft.is_empty() and GameSession.get_pastimes().postcards.size() == 1
		and GameSession.get_unpublished_renown() == renown + Pastimes.postcard_renown() and Pastimes.is_posted(companion.kind, companion.subject),
		"[postcards] finished: in the scrapbook, +%d renown" % Pastimes.postcard_renown())
	GameSession.set_postcard_draft(companion.kind, companion.subject, 0, "classic")
	var again := GameSession.work_on_postcard(120.0)
	t.check(again.done and (again.award as Dictionary).is_empty() and GameSession.get_unpublished_renown() == renown + Pastimes.postcard_renown()
		and GameSession.get_pastimes().postcards.size() == 2, "[postcards] the same subject again: a second card, no second reward")
	GameSession.set_postcard_draft("harbour", "copenhagen", 0, "classic")
	GameSession.abandon_postcard()
	t.check(GameSession.get_pastimes().draft.is_empty() and GameSession.postcard_minutes_left() == 120.0, "[postcards] an unfinished card can be thrown away")
	for kind in Pastimes.KINDS:
		t.check(Pastimes.captions(kind).size() == 3, "[postcards] three captions for %s" % kind)
	var caption := Pastimes.caption_text("voyage", 0, Pastimes.args_for("voyage", "copenhagen-helsingor"))
	t.check(caption.contains("Copenhagen") and caption.contains("Helsing"), "[postcards] a voyage card names both harbours (%s)" % caption)


func _test_game_dev() -> void:
	GameSession.start_new_session()
	var fits := func(task: Dictionary) -> bool:
		return int(task.hours) >= 2 and int(task.hours) <= 4 and (task.choices as Array).size() == 3 and (task.done as Array).size() == 3
	t.check(Pastimes.tasks().all(fits), "[game dev] every session is 2 to 4 hours, with three choices")
	var game := GameSession.get_pastimes().game
	var part := GameSession.work_on_game("feature", 0, 60.0)
	t.check(not part.done and absf(float(game.points) - 2.0 / 3.0) < 1e-6 and game.task.get("id") == "feature" and float(game.task.minutes) == 60.0,
		"[game dev] interrupted after 1 of 3 hours: a third of the points count, the session waits (%.2f)" % float(game.points))
	var rest := GameSession.work_on_game("feature", 0, 120.0)
	t.check(rest.done and absf(float(game.points) - 2.0) < 1e-6 and (game.task as Dictionary).is_empty() and int(game.sessions) == 1,
		"[game dev] going on: the whole session done, 2 points for the wise choice")
	var renown := GameSession.get_unpublished_renown()
	var odd := GameSession.work_on_game("bug", 2, 120.0)
	t.check(odd.done and not (odd.milestone as Dictionary).is_empty() and String(odd.milestone.id) == "keeper" and int(game.milestone) == 1
		and absf(float(game.points) - 0.0) < 1e-6 and GameSession.get_unpublished_renown() == renown + 4,
		"[game dev] an odd choice counts 1 point; 3 points: the first milestone, +4 renown")
	var funds := GameSession.get_funds()
	var guard := 0
	while not GameSession.is_game_released() and guard < 50:
		GameSession.work_on_game("arrange", 0, 180.0)
		guard += 1
	t.check(GameSession.is_game_released() and GameSession.get_funds() == funds + 300 and (game.log as Array).size() == Pastimes.milestones().size(),
		"[game dev] released after %d more sessions: the first sales pay %s, every milestone in the devlog" % [guard, GameSession.format_money(300)])
	var lifetime := GameSession.get_lifetime_renown()
	var after := GameSession.work_on_game("update", 0, 240.0)
	t.check(after.done and (after.award as Dictionary).is_empty() and GameSession.get_lifetime_renown() == lifetime and GameSession.get_funds() == funds + 300,
		"[game dev] after the release: small updates, no repeated rewards")
	var order := Pastimes.choice_order("bug", 0)
	var moved := range(4).any(func(n: int) -> bool: return Pastimes.choice_order("bug", n)[0] != 0)
	t.check(order.size() == 3 and moved, "[game dev] the choices are shown in a changing order (%s)" % [order])


func _test_pastime_saves() -> void:
	GameSession.start_new_session()
	GameSession.set_postcard_draft("companion", "cat", 1, "banner")
	GameSession.work_on_postcard(30.0)
	GameSession.work_on_game("balance", 1, 30.0)
	var back := _round_trip()
	t.check(back != null and back.pastimes.draft.get("minutes") == 30.0 and back.pastimes.draft.get("layout") == "banner"
		and back.pastimes.game.task.get("id") == "balance" and float(back.pastimes.game.task.minutes) == 30.0,
		"[saves] an unfinished postcard and game session are saved")
	var data: Dictionary = JSON.parse_string(JSON.stringify(GameSession.get_state_snapshot().to_dict()))
	data.erase("pastimes")
	var errors: Array[String] = []
	var old := SessionState.from_dict(data, errors)
	t.check(old != null and errors.is_empty() and old.pastimes.postcards.is_empty() and old.pastimes.draft.is_empty() and int(old.pastimes.game.milestone) == 0,
		"[old saves] a save from before the pastimes: an empty scrapbook and a game not yet begun")
	data["pastimes"] = {"postcards": [{"kind": 3}], "draft": "x", "game": {"points": "many", "milestone": -2, "task": {"id": 5}}}
	var odd := SessionState.from_dict(data, errors)
	t.check(odd != null and odd.pastimes.postcards.is_empty() and odd.pastimes.draft.is_empty() and float(odd.pastimes.game.points) == 0.0
		and int(odd.pastimes.game.milestone) == 0, "[saves] malformed pastimes are dropped quietly")


## Through App, on the one clock: the hours really pass (food is eaten), an
## arrival interrupts and the progress is kept.
func _test_pastimes_on_the_clock() -> void:
	GameSession.start_new_session()
	_moor_in(&"copenhagen")
	GameSession.set_postcard_draft("companion", String(GameSession.get_companion().kind), 0, "classic")
	var start := GameSession.get_game_time()
	var food := GameSession.get_provisions().food_days
	await app.make_postcard()
	t.check(absf(GameSession.get_game_time() - start - 7200.0) < 1.0 and GameSession.get_provisions().food_days < food
		and GameSession.get_pastimes().postcards.size() == 1, "[one clock] a postcard: two hours of the world pass, food is eaten as usual")
	GameSession.set_time_scale(20)
	start = GameSession.get_game_time()
	await app.work_on_game("bug", 0)
	t.check(absf(GameSession.get_game_time() - start - 7200.0) < 1.0 and GameSession.get_time_scale() == 1,
		"[one clock] a game session of 2 h; back at ×1 afterwards")
	# Find how long the short hop to Helsingør takes, then start a card an hour before arriving.
	var moored := GameSession.get_state_snapshot()
	t.check_eq(GameSession.plan_route_to(&"helsingor"), "", "(setup) course to Helsingør")
	t.check_eq(GameSession.depart(), "", "(setup) departed")
	var underway := GameSession.get_state_snapshot()
	var sailed := 0.0
	while GameSession.is_underway() and sailed < 48.0 * 3600.0:
		sailed += Simulation.advance(600.0, true).elapsed_seconds
	GameSession.replace_state(underway)
	Simulation.advance(sailed - 3600.0, false)
	if not t.check(GameSession.is_underway(), "(setup) underway, about an hour out (the hop takes %s)" % Simulation.format_duration(sailed)):
		GameSession.replace_state(moored)
		return
	GameSession.set_postcard_draft("companion", String(GameSession.get_companion().kind), 0, "classic")
	await app.make_postcard()
	var draft := GameSession.get_pastimes().draft
	t.check(not GameSession.is_underway() and not draft.is_empty() and float(draft.minutes) > 0.0 and float(draft.minutes) < 120.0
		and GameSession.get_pastimes().postcards.size() == 1, "[one clock] the arrival interrupts the card after %.0f min; it is kept to finish" % float(draft.get("minutes", 0)))
	t.check(Pastimes.subjects().any(func(s: Dictionary) -> bool: return s.kind == "voyage" and s.subject == "copenhagen-helsingor"),
		"[postcards] the voyage just made is a subject now")
	await app.make_postcard()
	t.check(GameSession.get_pastimes().draft.is_empty() and GameSession.get_pastimes().postcards.size() == 2, "[one clock] continued and finished later")


func _test_pastime_menus() -> void:
	app.modals.clear()
	await _settle()
	app.modals.clear()
	app._on_area_change_requested(&"interior", &"from_deck")
	await _settle()
	var wheel: Array = app.get_wheel_actions().map(func(a: Dictionary) -> StringName: return a.id)
	t.check(wheel.has(&"postcards") and wheel.has(&"game_dev") and wheel.has(&"log"), "[menus] the cabin's Q wheel offers both pastimes")
	var menu: PostcardMenu = app.open_postcards()
	if not t.check(menu != null, "[menus] Postcards from the Sea opens (gameplay %s, busy %s, modals %d %s, screen %s)" % [app.is_in_gameplay(),
			app.router.is_busy(), app.modals.depth(), app.modals.get_top(), app.router.current_screen]):
		return
	await t.frames(3)
	menu.choose(0, 1, "snapshot")
	t.check(menu.preview.card.get("layout") == "snapshot" and menu.find_child("Note", true, false).text.contains("2 h"),
		"[menus] the preview follows the choices; it says it takes about 2 hours (%s)" % menu.find_child("Note", true, false).text)
	await t.screenshot("i022_postcard")
	var cards := GameSession.get_pastimes().postcards.size()
	await t.click(menu.find_child("MakeButton", true, false))
	await t.frames(3)
	await t.wait_until(func() -> bool: return GameSession.get_pastimes().postcards.size() == cards + 1, 3.0)
	t.check(GameSession.get_pastimes().postcards.size() == cards + 1 and app.modals.is_empty(), "[menus] made and published from the menu")
	menu = app.open_postcards()
	await t.frames(2)
	await t.click(menu.find_child("ScrapbookButton", true, false))
	await t.frames(3)
	var book := app.modals.get_top() as ScrapbookMenu
	t.check(book != null and book.view.visible and book.view.card == GameSession.get_pastimes().postcards.back(), "[menus] the scrapbook opens on the newest card")
	await t.screenshot("i022_scrapbook")
	app.modals.clear()
	await t.frames(2)
	var dev: GameDevMenu = app.open_game_dev()
	if not t.check(dev != null, "[menus] the little game opens"):
		return
	await t.frames(3)
	t.check(dev.find_child("WorkButton", true, false).disabled, "[menus] no work before an answer is chosen")
	dev.pick(0)
	await t.frames(1)
	t.check(not dev.find_child("WorkButton", true, false).disabled and dev.find_child("Note", true, false).text.contains("h"),
		"[menus] the hours are shown before starting (%s)" % dev.find_child("WorkButton", true, false).text)
	await t.screenshot("i022_game_dev")
	var sessions := int(GameSession.get_pastimes().game.sessions)
	await t.click(dev.find_child("WorkButton", true, false))
	await t.wait_until(func() -> bool: return int(GameSession.get_pastimes().game.sessions) == sessions + 1, 3.0)
	t.check(int(GameSession.get_pastimes().game.sessions) == sessions + 1 and app.modals.is_empty(), "[menus] a session worked from the menu")


# --- Menus -----------------------------------------------------------------------------------------

func _test_menus() -> void:
	app.open_new_game_menu()
	await t.frames(3)
	var menu := app.modals.get_top() as NewGameMenu
	if not t.check(menu != null and menu.difficulty != null and menu.difficulty.level == Difficulty.STANDARD,
			"[menus] New Game offers the difficulty, Standard chosen"):
		return
	await t.click(menu.difficulty.find_child("Seasoned", true, false))
	await t.click(menu.find_child("StartButton", true, false))
	await _settle()
	t.check(GameSession.get_difficulty() == Difficulty.SEASONED and GameSession.get_funds() == Difficulty.starting_funds(Difficulty.SEASONED),
		"[menus] starting a Seasoned Captain's game")
	app.open_pause_menu()
	await t.frames(3)
	var pause: Node = app.modals.get_top()
	var button := pause.find_child("DifficultyButton", true, false) as Button if pause else null
	if not t.check(button != null, "[menus] the pause menu offers Difficulty…"):
		return
	await t.click(button)
	await t.frames(3)
	var dialog := app.modals.get_top() as DifficultyMenu
	if not t.check(dialog != null and dialog.picker.level == Difficulty.SEASONED, "[menus] the Difficulty dialog shows the current level"):
		return
	await t.screenshot("i022_difficulty")
	await t.click(dialog.picker.find_child("Relaxed", true, false))
	await t.click(dialog.find_child("ApplyButton", true, false))
	await t.frames(2)
	t.check(GameSession.get_difficulty() == Difficulty.RELAXED and app.modals.get_top() == pause, "[menus] applied, and the dialog closes back to the pause menu")
	app.modals.clear()
	await t.frames(2)
	t.check(app.modals.is_empty(), "[menus] everything opened can be closed")
