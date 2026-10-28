extends RefCounted
## Revision 0.102b: life at anchor and morning coffee. A safe evening at anchor
## settles the boat (a warm tint, the cabin lamp, the companion curled up),
## brings a few quiet lines without repeating them, waking at anchor has its
## own moment, and coffee is a small galley ritual whose Log moment comes once.
## Save/load at anchor and after coffee keeps all of it without duplicates.

const APP_SCENE := preload("res://src/app/app.tscn")
const W := preload("res://tests/helpers/walkability.gd")
const DECK := SessionState.AREA_EXTERIOR
const CABIN := SessionState.AREA_INTERIOR
const HOUR := 3600.0

var t: Node
var app: Node
var moments: Array = []


func run(runner: Node) -> void:
	t = runner
	Simulation.auto_advance = false
	t.use_calm_wind()
	_test_rules()
	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	app.start_new_game()
	await _settle()
	GameSession.anchor_moment.connect(_on_moment)
	await _test_coffee_in_harbour()
	if await _anchor():
		await _test_settling()
		await _test_evening()
		await _test_wake_and_coffee()
		await _test_save_load()
		await _test_unsettled()
	GameSession.anchor_moment.disconnect(_on_moment)
	Simulation.auto_advance = true
	app.queue_free()
	await t.frames(2)
	GameSession.end_session()
	t.use_calm_wind()


func _on_moment(kind: String, text: String) -> void:
	moments.append([kind, text])


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


func _shot(file_name: String, keep_notices := false) -> void:
	if not keep_notices:
		app.toasts.clear()
	app.hud.hide_warning()
	await t.frames(3)
	await t.screenshot(file_name)


## Advances game time until the boat's local hour is `hour` (at most a day).
func _advance_to_local_hour(hour: float) -> void:
	var now := GameSession.get_local_hour()
	var hours := fposmod(hour - now, 24.0)
	if hours > 0.01:
		Simulation.advance(hours * HOUR)


func _kinds() -> Array:
	return moments.map(func(m: Array) -> String: return m[0])


# --- Rules -------------------------------------------------------------------------------

func _test_rules() -> void:
	t.check(is_equal_approx(AnchorLife.local_hour(0.0, 15.0), 1.0) and is_equal_approx(AnchorLife.local_hour(0.0, -15.0), 23.0),
		"[rules] local solar hour from longitude (15° = 1 h)")
	t.check(AnchorLife.phase_at(7.0) == AnchorLife.PHASE_MORNING and AnchorLife.phase_at(13.0) == AnchorLife.PHASE_DAY
		and AnchorLife.phase_at(20.0) == AnchorLife.PHASE_EVENING and AnchorLife.phase_at(2.0) == AnchorLife.PHASE_NIGHT,
		"[rules] morning, day, evening, night")
	t.check(AnchorLife.TINTS[AnchorLife.PHASE_DAY] == Color.WHITE and AnchorLife.TINTS[AnchorLife.PHASE_EVENING].b < 0.8,
		"[rules] daylight leaves the scene as it is; the evening is warm")


# --- Coffee in harbour -------------------------------------------------------------------

func _test_coffee_in_harbour() -> void:
	var cabin := await _show(CABIN, &"from_deck")
	var menu: CookingMenu = app.open_cooking()
	if not t.check(menu != null, "[coffee] the galley opens in harbour"):
		return
	var button := menu.find_child("CoffeeButton", true, false) as Button
	t.check(button != null and not button.disabled, "[coffee] Make coffee is offered beside the dishes")
	var time := GameSession.get_game_time()
	var renown := GameSession.get_objective_progress().lifetime_renown
	button.pressed.emit()
	t.check(menu.is_brewing(), "[coffee] the pot goes on the stove")
	var result: Dictionary = menu.pour_coffee()
	await t.frames(2)
	t.check(result.error == "" and result.context == "harbour" and (result.award as Dictionary).is_empty()
		and menu.get_outcome_text().begins_with("Coffee is ready."), "[coffee] in harbour: %s" % menu.get_outcome_text().replace("\n", " / "))
	t.check(is_equal_approx(GameSession.get_game_time() - time, GameSession.COFFEE_MINUTES * 60.0), "[coffee] ten minutes pass")
	t.check(GameSession.get_objective_progress().lifetime_renown == renown, "[coffee] harbour coffee is flavour only: no reward")
	menu.close()
	await t.frames(2)
	t.check(cabin != null, "(setup) the cabin is shown")


# --- At anchor ---------------------------------------------------------------------------

## Copenhagen → Malmö until the coast is near and sheltered; drops anchor.
func _anchor() -> bool:
	t.set_wind(90.0, 8.0)
	GameSession.plan_route_to(&"malmo")
	if GameSession.depart() != "":
		return t.check(false, "(setup) under way to Malmö")
	for i in 200:
		Simulation.advance(300.0)
		var site := GameSession.evaluate_anchorage()
		if site.ok and String(site.class) == String(AnchorSite.CLASS_GOOD):
			break
	moments.clear()
	var dropped := GameSession.drop_anchor(5, 0.9)
	return t.check(dropped.error == "" and GameSession.is_anchored(), "(setup) at anchor near the Øresund coast (%s)" % dropped.error)


func _test_settling() -> void:
	t.check(GameSession.is_settled_at_anchor(), "[settle] holding well in a light wind: the boat is settled")
	t.check(moments.is_empty(), "[settle] no line at once: it comes once the boat has settled")
	var cabin := await _show(CABIN, &"from_deck")
	var companion := cabin.get_node_or_null(^"Companion") as ShipCompanion if cabin else null
	if t.check(companion != null, "(setup) the companion is below"):
		companion.advance_behaviour(30.0)
		t.check(companion.settled and companion.pose == CompanionVisualSet.POSE_SLEEPING,
			"[settle] the %s curls up for a nap (%s)" % [companion.kind, companion.pose])
		companion.advance_behaviour(120.0)
		t.check(companion.pose == CompanionVisualSet.POSE_SLEEPING or companion.pose == CompanionVisualSet.POSE_STRETCHING,
			"[settle] and keeps dozing (only a stretch between naps)")
	Simulation.advance(30.0 * 60.0)
	t.check(_kinds() == ["settled"], "[messages] after a while one quiet line: \"%s\"" % (moments[0][1] if not moments.is_empty() else ""))
	await _shot("0102b_03_cozy_anchored_message", true)
	Simulation.advance(2.0 * HOUR)
	t.check(_kinds().count("settled") == 1, "[messages] it is not repeated")


func _test_evening() -> void:
	_advance_to_local_hour(19.5)
	var cabin := await _show(CABIN, &"from_deck")
	t.check(_kinds().count("evening") == 1, "[messages] the evening brings one line (%s)" % [_kinds()])
	Simulation.advance(1.5 * HOUR)
	t.check(_kinds().count("evening") == 1, "[messages] still one evening line an hour and a half later")
	var ambience := cabin.get_anchor_ambience() if cabin else null
	if t.check(ambience != null, "[ambience] the cabin has its anchor ambience"):
		ambience.refresh(true)
		await t.frames(2)
		t.check(ambience.is_active() and ambience.get_tint().b < 0.95 and ambience.get_lamp_strength() > 0.1,
			"[ambience] a settled evening: warm tint %s, cabin lamp %.2f" % [ambience.get_tint(), ambience.get_lamp_strength()])
	t.check("quiet evening" in " ".join(app.hud.aboard_badge.get_texts()) or "calm night" in " ".join(app.hud.aboard_badge.get_texts()),
		"[ambience] the HUD says so: %s" % [app.hud.aboard_badge.get_texts()])
	await _shot("0102b_01_anchored_evening_cabin")
	var companion := cabin.get_node_or_null(^"Companion") as ShipCompanion
	if companion:
		companion.advance_behaviour(60.0)
		await _shot("0102b_02_companion_settled")
		companion.pet()
		companion.pet()
		t.check(_kinds().count("pet") == 1, "[companion] petting it on a settled evening: one soft line, once (%s)" % [_kinds()])
	var deck := await _show(DECK, &"start")
	if deck:
		deck.get_anchor_ambience().refresh(true)
		t.check(deck.get_anchor_ambience().is_active() and deck.get_anchor_ambience().get_lamp_strength() == 0.0,
			"[ambience] on deck the evening tint too (the lamp is below)")
		await _shot("0102b_01b_anchored_evening_deck")


func _test_wake_and_coffee() -> void:
	var before := moments.size()
	await _show(CABIN, &"from_deck")
	app.sleep_for(10.0)
	await _settle()
	var during := moments.slice(before)
	t.check(during.size() == 1 and during[0][0] == "wake", "[wake] nothing while asleep; waking brings one line (%s)" % [during])
	t.check(app.toasts.get_messages().size() >= 2 and app.toasts.get_messages()[-1] == (during[0][1] if not during.is_empty() else "?"),
		"[wake] shown after the waking notice: %s" % [app.toasts.get_messages()])
	t.check(GameSession.get_day_phase() in [AnchorLife.PHASE_MORNING, AnchorLife.PHASE_DAY], "[wake] it is morning (%.1f h)" % GameSession.get_local_hour())
	var cabin := app.router.current_screen as BoatArea
	if cabin and cabin.get_anchor_ambience():
		cabin.get_anchor_ambience().refresh(true)
	await _shot("0102b_04_wake_up_at_anchor", true)
	GameSession.begin_sleep()
	t.check(GameSession.end_sleep(5.0 * HOUR) == "", "[wake] the same day's wake-up line comes only once")
	# Morning coffee at anchor: the ritual and its Log moment, once.
	if GameSession.get_day_phase() != AnchorLife.PHASE_MORNING:
		_advance_to_local_hour(7.0)
	var menu: CookingMenu = app.open_cooking()
	if not t.check(menu != null, "[coffee] the galley opens at anchor"):
		return
	(menu.find_child("CoffeeButton", true, false) as Button).pressed.emit()
	await t.frames(6)
	await _shot("0102b_05_coffee_at_the_galley")
	var renown := GameSession.get_objective_progress().lifetime_renown
	var result: Dictionary = menu.pour_coffee()
	await t.frames(4)
	t.check(result.error == "" and result.context == "anchor_morning" and not (result.award as Dictionary).is_empty(),
		"[coffee] the first morning coffee at a quiet anchorage is a Log moment: %s" % result.text)
	t.check(GameSession.get_objective_progress().lifetime_renown == renown + 2, "[coffee] with a little renown (+2)")
	await _shot("0102b_06_coffee_result", true)
	var again: Dictionary = menu.pour_coffee()
	t.check(again.error == "" and (again.award as Dictionary).is_empty() and GameSession.get_objective_progress().lifetime_renown == renown + 2,
		"[coffee] a second cup: just coffee, no second reward")
	var log_count := GameSession.get_aboard_moments().filter(func(m: Dictionary) -> bool: return String(m.text).begins_with("Morning coffee")).size()
	t.check(log_count == 1, "[coffee] the Captain's Log keeps it once")
	menu.close()
	await t.frames(2)


func _test_save_load() -> void:
	var anchor_before := GameSession.get_anchor().moments.duplicate()
	t.check_eq(SaveManager.save_to_slot(3, GameSession.get_state_snapshot()), OK, "[save] saved at anchor after coffee")
	var count := moments.size()
	app.load_slot(3)
	await _settle()
	t.check(GameSession.is_anchored() and GameSession.is_settled_at_anchor() and GameSession.get_anchor().moments == anchor_before,
		"[save] loaded: still settled at anchor, the stay's moments kept (%s)" % [GameSession.get_anchor().moments])
	Simulation.advance(20.0 * 60.0)
	t.check(moments.size() == count, "[save] no moment repeats after loading")
	t.check(GameSession.get_objective_progress().is_completed(&"coffee:morning_at_anchor"), "[save] the coffee moment is kept")
	# An Iteration 14 save has no "moments": it loads, with an empty list.
	var path: String = SaveManager._slot_path(3)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	data.session.anchor.erase("moments")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t", true, true))
	file.close()
	var loaded := SaveManager.load_from_slot(3)
	t.check(loaded.is_ok() and loaded.state.anchor.active and loaded.state.anchor.moments.is_empty(),
		"[save] a 0.102a save (no moments) loads at anchor (%s)" % loaded.error)
	SaveManager.delete_slot(3)


func _test_unsettled() -> void:
	var cabin := await _show(CABIN, &"from_deck")
	var companion := cabin.get_node_or_null(^"Companion") as ShipCompanion
	t.set_wind(90.0, 24.0)
	Simulation.advance(20.0 * 60.0)
	t.check(not GameSession.is_settled_at_anchor(), "[unsettled] a fresh breeze: no longer settled")
	if cabin.get_anchor_ambience():
		cabin.get_anchor_ambience().refresh(true)
		t.check(not cabin.get_anchor_ambience().is_active(), "[unsettled] the scene looks as usual again")
	if companion:
		companion.advance_behaviour(10.0)
		t.check(not companion.settled and companion.pose != CompanionVisualSet.POSE_SLEEPING,
			"[unsettled] the companion wakes from its nap (%s)" % companion.pose)
	t.use_calm_wind()
	t.set_wind(90.0, 6.0)
	Simulation.advance(10.0 * 60.0)
	GameSession.raise_anchor()
	t.check(not GameSession.is_settled_at_anchor(), "[unsettled] anchor up: the stay is over")
	# Coffee refusals stay gentle and change nothing.
	t.set_wind(90.0, 30.0)
	var time := GameSession.get_game_time()
	var refused := GameSession.make_coffee()
	t.check(refused.error.contains("Too lively") and GameSession.get_game_time() == time, "[coffee] underway in a gale: \"%s\"" % refused.error)
	t.use_calm_wind()
