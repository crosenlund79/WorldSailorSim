extends RefCounted
## Iteration 005c: a sailor's living. Remote work in harbour (1-8 h, EUR 25 per
## completed hour, time and stores used as usual), the harbour grocery store
## (EUR 10 per missing day of food and water combined), the end of free
## restocking, repairs still free, and persistence. Core rules first, then the
## real application (stations on all three boats, menus).

const APP_SCENE := preload("res://src/app/app.tscn")
const W := preload("res://tests/helpers/walkability.gd")
const VESSELS: Array[StringName] = [&"arctic_wanderer_26", &"starling_33", &"halcyon_40", &"petrel_36"]
const HOUR := 3600.0

var t: Node
var app: Node


func run(runner: Node) -> void:
	t = runner
	Simulation.auto_advance = false
	t.use_calm_wind()
	WeatherFixtures.clear()
	_test_remote_work()
	_test_grocery_prices()
	_test_no_free_restock()
	_test_persistence()
	GameSession.end_session()

	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	app.start_new_game()
	await _settle()
	await _test_work_station()
	await _test_grocery_store()
	Simulation.auto_advance = true
	app.queue_free()
	await t.frames(2)
	GameSession.end_session()
	t.use_calm_wind()


func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)


func _set_funds(euros: int) -> void:
	var state := GameSession.get_state_snapshot()
	state.funds = euros
	GameSession.replace_state(state)


# --- Remote work ------------------------------------------------------------------------

func _test_remote_work() -> void:
	GameSession.start_new_session()
	var start := GameSession.get_game_time()
	var result := Simulation.work(4)
	t.check(result.error == "" and result.hours == 4 and result.earned == 100, "[work] 4 hours in harbour earn €100 (%s)" % [result])
	t.check_eq(GameSession.get_funds(), 10100, "[work] funds €10,100")
	t.check(is_equal_approx(GameSession.get_game_time() - start, 4.0 * HOUR), "[work] 4 hours of game time pass")
	t.check(absf(GameSession.get_food_days() - (14.0 - 4.0 / 24.0)) < 1e-6 and absf(GameSession.get_water_days() - (14.0 - 4.0 / 24.0)) < 1e-6,
		"[work] food and water are used as usual (%.4f days left)" % GameSession.get_food_days())
	var eight := Simulation.work(12)
	t.check(eight.hours == 8 and eight.earned == 200, "[work] at most 8 hours per session (%s)" % [eight])
	var one := Simulation.work(0)
	t.check(one.hours == 1 and one.earned == 25, "[work] at least 1 hour")
	t.check_eq(GameSession.get_funds(), 10325, "[work] 13 hours in all: €325 earned")
	# Paused: work still moves time on, and the pause stays.
	GameSession.set_paused(true)
	var paused_time := GameSession.get_game_time()
	Simulation.work(2)
	t.check(GameSession.is_paused() and is_equal_approx(GameSession.get_game_time() - paused_time, 2.0 * HOUR) and GameSession.get_funds() == 10375,
		"[work] while paused: 2 hours pass, €50 paid, still paused")
	GameSession.set_paused(false)
	# Same stores as simply letting the time pass.
	var a := GameSession.get_food_days()
	Simulation.work(6)
	var worked := GameSession.get_food_days()
	GameSession.start_new_session()
	Simulation.advance(21.0 * HOUR)  # 4 + 8 + 1 + 2 + 6 hours of work above
	t.check(absf(GameSession.get_food_days() - worked) < 1e-6 and a > worked, "[work] uses exactly the stores of the same time passing")
	# Not at sea.
	GameSession.plan_route_to(&"kiel")
	GameSession.depart()
	var funds := GameSession.get_funds()
	var time := GameSession.get_game_time()
	var refused := Simulation.work(3)
	t.check(not String(refused.error).is_empty() and GameSession.get_funds() == funds and GameSession.get_game_time() == time,
		"[work] refused at sea: no money, no time passes (%s)" % refused.error)


# --- Grocery store --------------------------------------------------------------------------

func _test_grocery_prices() -> void:
	GameSession.start_new_session()
	t.check_eq(GameSession.get_provisions_price(), 0, "[grocery] full stores cost nothing to fill")
	t.check(GameSession.buy_provisions().contains("already full"), "[grocery] and buying is refused")
	GameSession.set_provisions_for_testing(10.25)
	t.check_eq(GameSession.get_provisions_price(), 75, "[grocery] 3.75 + 3.75 missing days cost €75")
	GameSession.set_provisions_for_testing(10.2)
	t.check_eq(GameSession.get_provisions_price(), 76, "[grocery] 3.8 + 3.8 days: €76")
	GameSession.set_provisions_for_testing(13.99)
	t.check_eq(GameSession.get_provisions_price(), 1, "[grocery] a fraction of a day is rounded up, never free (€1)")
	GameSession.set_provisions_for_testing(0.0)
	t.check_eq(GameSession.get_provisions_price(), 280, "[grocery] empty stores: 28 days, €280")
	# Not enough money: nothing changes.
	_set_funds(279)
	var refused := GameSession.buy_provisions()
	t.check(refused.contains("Not enough money") and GameSession.get_funds() == 279 and GameSession.get_food_days() == 0.0,
		"[grocery] €279 is not enough for €280: refused, nothing changes (%s)" % refused)
	# Exactly enough.
	_set_funds(280)
	t.check_eq(GameSession.buy_provisions(), "", "[grocery] with €280 it works")
	t.check(GameSession.get_funds() == 0 and is_equal_approx(GameSession.get_food_days(), 14.0) and is_equal_approx(GameSession.get_water_days(), 14.0),
		"[grocery] €0 left, food and water both 14 days")
	# Food and water missing different amounts count together.
	var state := GameSession.get_state_snapshot()
	state.funds = 1000
	state.provisions.food_days = 4.0
	state.provisions.water_days = 12.5
	GameSession.replace_state(state)
	t.check_eq(GameSession.get_provisions_price(), 115, "[grocery] 10 days of food and 1.5 of water: €115")
	GameSession.buy_provisions()
	t.check_eq(GameSession.get_funds(), 885, "[grocery] paid €115")
	# At sea: no grocery store.
	GameSession.set_provisions_for_testing(5.0)
	GameSession.plan_route_to(&"kiel")
	GameSession.depart()
	t.check(GameSession.buy_provisions().contains("harbour") and GameSession.get_funds() == 885, "[grocery] not at sea")
	# Every harbour sells at the same price (no regional prices).
	var prices := []
	for port_id in [&"copenhagen", &"lisbon", &"piraeus"]:
		var s := GameSession.get_state_snapshot()
		s.voyage = null
		s.vessel_status = SessionState.STATUS_MOORED
		s.location_id = port_id
		s.vessel_position = PortCatalog.get_default().get_port(port_id).get_geo_position()
		s.provisions.food_days = 7.0
		s.provisions.water_days = 7.0
		GameSession.replace_state(s)
		prices.append(GameSession.get_provisions_price())
	t.check(prices == [140, 140, 140], "[grocery] the same price in every harbour (%s)" % [prices])


func _test_no_free_restock() -> void:
	t.check(not GameSession.has_method("restock_provisions"), "[grocery] the free restock action no longer exists")
	GameSession.start_new_session()
	GameSession.set_condition_for_testing(30.0)
	var cost := int(GameSession.service_quote(BoatCare.SERVICE_REPAIR).cost)
	t.check(GameSession.repair_vessel() == "" and cost > 0 and GameSession.get_funds() == 10000 - cost
		and is_equal_approx(GameSession.get_condition(), 100.0), "[repair] repairs cost their quote (€%d for 70 %% damage)" % cost)


func _test_persistence() -> void:
	GameSession.start_new_session()
	Simulation.work(5)
	GameSession.set_provisions_for_testing(6.0)
	GameSession.buy_provisions()
	var expected := GameSession.get_funds()
	t.check_eq(expected, 10125 - 160, "[saves] (setup) earned €125, spent €160")
	t.check_eq(SaveManager.save_to_slot(2, GameSession.get_state_snapshot()), OK, "[saves] saved")
	var loaded := SaveManager.load_from_slot(2)
	t.check(loaded.is_ok() and loaded.state.funds == expected and is_equal_approx(loaded.state.provisions.food_days, 14.0),
		"[saves] money and stores after working and shopping are restored")
	SaveManager.delete_slot(2)


# --- In the game ------------------------------------------------------------------------------

func _station(area: BoatArea, interaction_id: StringName) -> Interactable:
	for node: Interactable in area.get_node("Layout/Stations").get_children():
		if node.interaction_id == interaction_id:
			return node
	return null


func _show(area: StringName, spawn: StringName) -> void:
	app.modals.clear()
	GameSession.enter_boat_area(area, spawn)
	app._show_current_boat_area()
	await _settle()


## Stands where `interaction_id` is focused and presses E.
func _use(interaction_id: StringName) -> bool:
	var area := app.router.current_screen as BoatArea
	var station := _station(area, interaction_id)
	if station == null or not station.enabled:
		return false
	var cells := W.walkable_cells(area, area.get_spawn_position(&"start" if area.area_id == SessionState.AREA_INTERIOR else &"from_boatyard"))
	var tries := 0
	for p in W.use_points(station, cells):
		area.player.position = p
		area.player.set_facing((station.global_position - p).normalized())
		await t.physics_frames(3)
		if area.player.get_focused_interactable() == station:
			await t.press_action(&"interact")
			await t.frames(2)
			return true
		tries += 1
		if tries > 40:
			break
	return false


func _test_work_station() -> void:
	for id in VESSELS:
		GameSession.switch_vessel(id)
		await _show(SessionState.AREA_INTERIOR, &"start")
		var area := app.router.current_screen as BoatArea
		var station := _station(area, &"work")
		t.check(station != null and station.prompt == "Use the laptop" and area.get_laptop() != null, "[work] the %s's cabin has its laptop on the table" % id)
		t.check(await _use(&"work") and app.modals.get_top() is LaptopView, "[work] on the %s it opens the laptop" % id)
		app.modals.clear()
		await t.frames(2)
	GameSession.switch_vessel(&"starling_33")
	await _show(SessionState.AREA_INTERIOR, &"start")
	await _use(&"work")
	var laptop := app.modals.get_top() as LaptopView
	await t.click(laptop.get_content().find_child("WorkButton", true, false) as Button)
	await t.frames(2)
	var menu := laptop.task as WorkMenu
	if not t.check(menu != null, "[work] the dialog is open"):
		return
	t.check_eq(menu.hours, WorkMenu.DEFAULT_HOURS, "[work] it suggests 4 hours")
	var work_button := menu.find_child("WorkButton", true, false) as Button
	t.check(work_button.text == "Work 4 h for €100", "[work] the button names hours and pay (%s)" % work_button.text)
	for i in 6:
		await t.click(menu.find_child("IncreaseButton", true, false) as Button)
	t.check(menu.hours == 8 and (menu.find_child("IncreaseButton", true, false) as Button).disabled, "[work] at most 8 hours")
	await t.screenshot("105_remote_work")
	var funds := GameSession.get_funds()
	var time := GameSession.get_game_time()
	await t.click(work_button)
	await _settle()
	t.check(GameSession.get_funds() == funds + 200 and is_equal_approx(GameSession.get_game_time() - time, 8.0 * HOUR) and app.modals.is_empty(),
		"[work] working 8 hours earns €200 and takes 8 hours")
	var reported := false
	for message in app.toasts.get_messages():
		reported = reported or (message.contains("earned €200") and message.contains("8 h"))
	t.check(reported, "[work] the pay is reported")
	# At sea the station refuses politely.
	GameSession.plan_route_to(&"kiel")
	GameSession.depart()
	await _settle()
	app.open_work_menu()
	var refused := false
	for message in app.toasts.get_messages():
		refused = refused or message.contains("moor in a harbour")
	t.check(app.open_work_menu() == null and refused, "[work] at sea there is no remote work")


func _test_grocery_store() -> void:
	app.start_new_game()
	await _settle()
	for id in VESSELS:
		GameSession.switch_vessel(id)
		await _show(SessionState.AREA_EXTERIOR, &"from_boatyard")
		var area := app.router.current_screen as BoatArea
		var station := _station(area, &"grocery")
		var sign := area.find_child("GrocerySign", true, false) as Label
		t.check(station != null and station.enabled and sign != null and sign.is_visible_in_tree(),
			"[grocery] the %s's pontoon has a grocery store, signposted" % id)
		t.check(await _use(&"grocery") and app.modals.get_top() is GroceryMenu, "[grocery] on the %s it opens the store" % id)
		app.modals.clear()
		await t.frames(2)
	GameSession.switch_vessel(&"starling_33")
	await _show(SessionState.AREA_EXTERIOR, &"from_boatyard")
	GameSession.set_provisions_for_testing(4.5)
	await _use(&"grocery")
	var store := app.modals.get_top() as GroceryMenu
	if not t.check(store != null, "[grocery] the store is open"):
		return
	t.check(store.get_buy_button().text == "Buy for €190" and not store.get_buy_button().disabled,
		"[grocery] it offers 9.5 + 9.5 days for €190 (%s)" % store.get_buy_button().text)
	await t.screenshot("106_grocery_store")
	await t.click(store.get_buy_button())
	await t.frames(2)
	t.check(GameSession.get_funds() == 9810 and is_equal_approx(GameSession.get_food_days(), 14.0) and store.get_buy_button().disabled,
		"[grocery] bought: €9,810 left, full stores, nothing more to buy")
	store.close()
	await t.frames(2)
	# Too little money: the store says so and does not sell.
	_set_funds(30)
	await _show(SessionState.AREA_EXTERIOR, &"from_boatyard")
	GameSession.set_provisions_for_testing(2.0)
	await _use(&"grocery")
	store = app.modals.get_top() as GroceryMenu
	var note := (store.find_child("Note", true, false) as Label).text if store else ""
	t.check(store != null and store.get_buy_button().disabled and note.contains("Not enough money") and note.contains("Remote work"),
		"[grocery] €30 for €240 of provisions: Buy disabled, the store explains and points to remote work")
	await t.screenshot("107_grocery_not_enough_money")
	app.modals.clear()
	await t.frames(2)
	# At sea the pontoon (and its store) is not there.
	_set_funds(10000)
	GameSession.plan_route_to(&"kiel")
	GameSession.depart()
	await _show(SessionState.AREA_EXTERIOR, &"from_cabin")
	var away := _station(app.router.current_screen as BoatArea, &"grocery")
	t.check(away != null and not away.enabled and not away.visible, "[grocery] underway the grocery store is gone")
