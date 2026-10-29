extends RefCounted
## I027 Tier 2, the cost of the wind: fuel and the running costs of a life
## afloat. The balance file read in one place (Economy); the engine burning
## fuel in the step that moves the boat under engine and nothing under sail;
## an empty tank leaving the sails (never stranded, never a free engine); fuel
## bought at the berth with what the money allows; harbour dues charged once
## for the nights moored, waived beyond the money, nothing for a short stop or
## at anchor; every euro in the career's books by source; a voyage's own
## figures on arrival; all of it through a save, and an older save without
## it; the fuel berth on every quay; Relaxed gentler.

const APP_SCENE := preload("res://src/app/app.tscn")

var t: Node


func run(runner: Node) -> void:
	t = runner
	Simulation.auto_advance = false
	_test_data()
	_test_burn()
	_test_empty_tank()
	_test_buy_fuel()
	_test_dues()
	_test_ledger_and_voyage()
	_test_motor_upwind()
	_test_save()
	await _test_fuel_berth()
	Simulation.auto_advance = true
	t.use_calm_wind()
	GameSession.end_session()


func _new_game(level: StringName = Difficulty.STANDARD) -> void:
	GameSession.start_new_session(&"", level)
	t.use_calm_wind()


func _test_data() -> void:
	var boats := [&"arctic_wanderer_26", &"starling_33", &"petrel_36", &"halcyon_40"]
	var ok := true
	for id: StringName in boats:
		ok = ok and Economy.tank_l(id) > 0.0 and Economy.burn_lph(id) > 0.0
	t.check(ok, "[data] every boat has a tank and a burn rate in the balance file")
	t.check(Economy.tank_l(&"halcyon_40") > Economy.tank_l(&"arctic_wanderer_26") and Economy.burn_lph(&"halcyon_40") > Economy.burn_lph(&"arctic_wanderer_26"),
		"[data] the catamaran's twin diesels hold and burn more than the 26 ft's small engine")
	var med := Economy.fuel_price_per_litre(&"naples")
	var nordic := Economy.fuel_price_per_litre(&"copenhagen")
	t.check(med > 1.0 and nordic > 1.0 and not is_equal_approx(med, nordic), "[data] fuel prices vary by region (Naples €%.2f, Copenhagen €%.2f)" % [med, nordic])
	t.check(Economy.dues_per_night(&"copenhagen", 40.0) > Economy.dues_per_night(&"copenhagen", 26.0), "[data] a longer boat pays more dues")
	t.check(Economy.dues_per_night(&"copenhagen", 30.0) > Economy.dues_per_night(&"lohals", 30.0), "[data] a major harbour charges more than a small one")
	t.check(Economy.nights(&"copenhagen", 1000000.0, 1000000.0 + 3600.0) == 0, "[data] a short stop is no night")


func _test_burn() -> void:
	_new_game()
	GameSession.plan_route_to(&"gothenburg")
	GameSession.depart()  # calm: the engine
	var start := GameSession.get_fuel_l()
	var nm0 := GameSession.get_ledger().nm_engine
	Simulation.advance(2.0 * 3600.0)
	var burned := start - GameSession.get_fuel_l()
	var expected := Economy.burn_lph(GameSession.get_vessel_id()) * 2.0
	t.check(GameSession.get_propulsion().is_motoring() and absf(burned - expected) < 0.05,
		"[burn] two hours under engine in a calm: %.2f litres (%.2f expected)" % [burned, expected])
	t.check(GameSession.get_ledger().nm_engine - nm0 > 5.0 and absf(GameSession.get_ledger().fuel_burned_l - burned) < 0.05, "[burn] the books know the miles and the litres")
	# A fair breeze: under sail no fuel is burned (each 5-minute step spent
	# under sail, with the wind kept abeam of the leg).
	var sail_steps := 0
	var burned_sailing := 0.0
	for i in 72:
		if not GameSession.is_underway():
			break
		var voyage := GameSession.get_voyage()
		t.set_wind(fposmod(voyage.leg_bearing_at(voyage.progress_nm) + 100.0, 360.0), 15.0)
		var sailing_before := not GameSession.get_propulsion().is_motoring()
		var litres := GameSession.get_fuel_l()
		Simulation.advance(300.0)
		if sailing_before and not GameSession.get_propulsion().is_motoring():
			sail_steps += 1
			burned_sailing += litres - GameSession.get_fuel_l()
	t.check(sail_steps >= 20 and burned_sailing == 0.0, "[burn] under sail the tank stays as it is (%d steps under sail, %.3f litres)" % [sail_steps, burned_sailing])


func _test_empty_tank() -> void:
	_new_game()
	GameSession.plan_route_to(&"gothenburg")
	var state := GameSession.get_state_snapshot()
	state.fuel[state.vessel_id] = 0.5
	GameSession.replace_state(state)
	GameSession.depart()
	Simulation.advance(1800.0)
	t.check(GameSession.get_fuel_l() <= 0.01, "[empty] the last half litre burns")
	Simulation.advance(1800.0)
	var progress := GameSession.get_voyage_progress_nm()
	Simulation.advance(3600.0)
	t.check(not GameSession.get_propulsion().is_motoring(), "[empty] with an empty tank no engine (no free motoring)")
	t.check(absf(GameSession.get_voyage_progress_nm() - progress) < 0.5, "[empty] becalmed without fuel the boat waits for wind")
	t.set_wind(fposmod(Simulation.get_current_heading() + 90.0, 360.0), 12.0)
	Simulation.evaluate_propulsion(true, true)
	Simulation.advance(3600.0)
	t.check(GameSession.get_voyage_progress_nm() - progress > 2.0, "[empty] and sails on when it comes (never stranded)")


func _test_buy_fuel() -> void:
	_new_game()
	var state := GameSession.get_state_snapshot()
	state.fuel[state.vessel_id] = 5.0
	GameSession.replace_state(state)
	var funds := GameSession.get_funds()
	var per_litre := GameSession.get_fuel_price()
	var result := GameSession.buy_fuel()
	var space := GameSession.get_fuel_tank_l() - 5.0
	t.check(result.error == "" and is_equal_approx(GameSession.get_fuel_l(), GameSession.get_fuel_tank_l())
		and GameSession.get_funds() == funds - ceili(space * per_litre), "[buy] fill up: %.1f litres for %s" % [float(result.litres), GameSession.format_money(int(result.price))])
	t.check(GameSession.buy_fuel().error != "", "[buy] a full tank takes no more")
	t.check(GameSession.get_ledger().total("fuel") == -int(result.price), "[buy] in the books as fuel")
	# Little money: what it allows, never below zero.
	state = GameSession.get_state_snapshot()
	state.fuel[state.vessel_id] = 0.0
	state.funds = 20
	GameSession.replace_state(state)
	result = GameSession.buy_fuel()
	t.check(result.error == "" and GameSession.get_funds() >= 0 and GameSession.get_fuel_l() > 0.0 and GameSession.get_fuel_l() < GameSession.get_fuel_tank_l(),
		"[buy] with €20 a part of a tank (%.1f litres, €%d left)" % [GameSession.get_fuel_l(), GameSession.get_funds()])
	# Relaxed pays less.
	_new_game(Difficulty.RELAXED)
	var relaxed := GameSession.get_fuel_price()
	_new_game(Difficulty.STANDARD)
	t.check(relaxed < GameSession.get_fuel_price(), "[buy] Relaxed: fuel costs less (€%.2f vs €%.2f)" % [relaxed, GameSession.get_fuel_price()])
	# At sea there is no fuel berth.
	GameSession.plan_route_to(&"gothenburg")
	GameSession.depart()
	t.check(GameSession.buy_fuel().error != "", "[buy] at sea: no fuel berth")


func _test_dues() -> void:
	_new_game()
	var per_night := GameSession.get_harbour_dues_per_night()
	t.check(per_night > 0, "[dues] Copenhagen: %s a night for the 26 ft" % GameSession.format_money(per_night))
	Simulation.advance(2.0 * 86400.0)
	var funds := GameSession.get_funds()
	GameSession.plan_route_to(&"gothenburg")
	GameSession.depart()
	var paid := funds - GameSession.get_funds()
	t.check(paid >= per_night * 2 - 1 and paid <= per_night * 3, "[dues] two days moored, paid on leaving: %s (%s a night)" % [GameSession.format_money(paid), GameSession.format_money(per_night)])
	t.check(GameSession.get_ledger().total("harbour_dues") == -paid, "[dues] in the books once")
	# A short stop costs nothing.
	_new_game()
	Simulation.advance(2.0 * 3600.0)
	funds = GameSession.get_funds()
	GameSession.plan_route_to(&"gothenburg")
	GameSession.depart()
	t.check(GameSession.get_funds() == funds, "[dues] a two-hour stop: no dues")
	# Without the money the harbourmaster lets the rest go.
	_new_game()
	Simulation.advance(3.0 * 86400.0)
	var state := GameSession.get_state_snapshot()
	state.funds = 5
	GameSession.replace_state(state)
	GameSession.plan_route_to(&"gothenburg")
	t.check(GameSession.depart() == "" and GameSession.get_funds() == 0, "[dues] with €5: €5 paid, the rest waived, away all the same")


func _test_ledger_and_voyage() -> void:
	_new_game()
	GameSession.buy_provisions()
	var state := GameSession.get_state_snapshot()
	state.fuel[state.vessel_id] = 10.0
	GameSession.replace_state(state)
	GameSession.buy_fuel()
	GameSession.plan_route_to(&"helsingor")
	GameSession.depart()
	var guard := 0
	while GameSession.is_underway() and guard < 200:
		Simulation.advance(1800.0)
		guard += 1
	var ledger := GameSession.get_ledger()
	t.check(ledger.total("fuel") < 0 and ledger.entries.size() >= 1, "[ledger] every euro by its source %s" % [ledger.totals])
	var last: Dictionary = ledger.voyages.back() if not ledger.voyages.is_empty() else {}
	t.check(not last.is_empty() and String(last.to) == "helsingor" and float(last.fuel_l) > 0.0 and float(last.nm_engine) > 0.0,
		"[ledger] the voyage to Helsingør on record: %.1f nm under engine, %.1f litres" % [float(last.get("nm_engine", 0.0)), float(last.get("fuel_l", 0.0))])


## The choice to windward: beat under sail (no fuel) or motor straight up.
func _test_motor_upwind() -> void:
	var made := {}
	var fuel := {}
	for motor: bool in [false, true]:
		_new_game()
		GameSession.set_motor_upwind(motor)
		GameSession.plan_route_to(&"gothenburg")
		t.set_wind(0.0, 13.0)
		GameSession.depart()
		for i in 24:
			Simulation.advance(300.0)
		var from := GameSession.get_voyage_progress_nm()
		var litres := GameSession.get_fuel_l()
		for i in 48:
			var voyage := GameSession.get_voyage()
			t.set_wind(voyage.leg_bearing_at(voyage.progress_nm), 13.0)
			Simulation.advance(300.0)
		made[motor] = GameSession.get_voyage_progress_nm() - from
		fuel[motor] = litres - GameSession.get_fuel_l()
	t.check(float(made[true]) > float(made[false]) and float(fuel[true]) > 0.5 and float(fuel[false]) < float(fuel[true]),
		"[choice] four hours to windward: beating %.1f nm on %.1f litres, motoring %.1f nm on %.1f litres" % [float(made[false]), float(fuel[false]),
		float(made[true]), float(fuel[true])])
	t.check(GameSession.get_propulsion().describe().contains("as you chose"), "[choice] the engine says why: '%s'" % GameSession.get_propulsion().describe())
	var data: Dictionary = GameSession.get_state_snapshot().to_dict()
	var errors: Array[String] = []
	t.check(SessionState.from_dict(data, errors).motor_upwind, "[choice] kept in the save")


func _test_save() -> void:
	_new_game()
	GameSession.plan_route_to(&"gothenburg")
	GameSession.depart()
	Simulation.advance(3600.0)
	var state := GameSession.get_state_snapshot()
	var data: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	var errors: Array[String] = []
	var loaded := SessionState.from_dict(data, errors)
	t.check(loaded != null and absf(float(loaded.fuel.get(state.vessel_id, -1.0)) - float(state.fuel[state.vessel_id])) < 1e-6
		and loaded.ledger.fuel_burned_l > 0.0 and not loaded.ledger.open_voyage.is_empty(), "[save] fuel, the books and the open voyage saved %s" % [errors])
	var old := data.duplicate(true)
	old.erase("fuel")
	old.erase("ledger")
	old.erase("moored_since")
	var old_errors: Array[String] = []
	var old_state := SessionState.from_dict(old, old_errors)
	t.check(old_state != null and old_state.fuel.is_empty() and old_state.ledger.entries.is_empty(), "[save] an older save loads: a full tank, empty books %s" % [old_errors])
	_new_game()
	var moored := GameSession.get_state_snapshot()
	moored.moored_since = 0.0
	GameSession.replace_state(moored)
	t.check(is_equal_approx(GameSession.get_state_snapshot().moored_since, GameSession.get_game_time()), "[save] an older save in harbour: dues count from loading, not before")
	t.check(is_equal_approx(GameSession.get_fuel_l(), GameSession.get_fuel_tank_l()), "[save] and its boat has a full tank")


func _test_fuel_berth() -> void:
	var lohals := QuayLayout.build(&"lohals")
	var cph := QuayLayout.build(&"copenhagen")
	t.check(lohals.fuel_berth != Vector2.ZERO and cph.fuel_berth != Vector2.ZERO, "[berth] a fuel berth on every quay, small or major")
	var app: Node = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await t.frames(3)
	app.start_new_game()
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	var state := GameSession.get_state_snapshot()
	state.fuel[state.vessel_id] = 3.0
	GameSession.replace_state(state)
	var front: HarbourFront = await TestQuay.go_up(t, app)
	var station := front.get_station(HarbourFront.FUEL) if front else null
	t.check(station != null and station.prompt.contains("€"), "[berth] the pump on the quay, its price in the prompt ('%s')" % (station.prompt if station else "-"))
	if station:
		var used := await TestQuay.use_door(t, app, HarbourFront.FUEL, false)
		var menu := app.modals.get_top() as FuelMenu
		t.check(used and menu != null and menu.has_node(^"FocusFrame"), "[berth] E at the pump: the fuel menu, at any hour")
		if menu:
			await t.click(menu.find_child("FillButton", true, false) as Button)
			await t.frames(2)
			t.check(is_equal_approx(GameSession.get_fuel_l(), GameSession.get_fuel_tank_l()), "[berth] Fill up fills the tank")
			await t.screenshot("i027_fuel_berth")
		app.modals.clear()
	t.check(Hud.describe_status().contains("Fuel"), "[hud] the fuel on the status line ('%s')" % Hud.describe_status())
	var lines := HarbourOfficeMenu.running_cost_lines()
	t.check(lines.size() >= 3 and lines[0].contains("a night") and lines[1].contains("litre"), "[office] running costs: %s" % [lines])
	app.queue_free()
	await t.frames(2)
