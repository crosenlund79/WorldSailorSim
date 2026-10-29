extends RefCounted
## Iteration 16, the Copenhagen-to-Paradise test: the Arctic Wanderer 26, the
## smallest boat, sails from Copenhagen through Danish waters, across the
## Atlantic by the island harbours, through the Panama passage and across the
## Pacific to Tahiti, on the real (seeded) wind and weather, in Long Passage
## time. On the way: passage stores, readiness, an intermediate harbour with
## mooring, gangplank and Go Ashore, fishing and cooking, a save and reload in
## the middle of the ocean. Nothing is teleported: every mile is sailed by
## the simulation.

const APP_SCENE := preload("res://src/app/app.tscn")
const DECK := SessionState.AREA_EXTERIOR
## The voyage in legs, each a passage between harbours.
const LEGS: Array = [
	[&"copenhagen", &"las_palmas"],
	[&"las_palmas", &"castries"],
	[&"castries", &"colon"],
	[&"colon", &"panama_city"],
	[&"panama_city", &"puerto_ayora"],
	[&"puerto_ayora", &"taiohae"],
	[&"taiohae", &"papeete"],
]
const SEED := 16
## Long Passage at 12 hours a second, in ticks of 0.1 s (72 game minutes each).
const RATE := 43200.0
const TICK := 0.1

var t: Node
var app: Node
var _interruptions := {}
var _regions_seen := {}
var _bites := 0
var _meals := 0
var _dateline_ok := true
## Game day of the last fishing stretch and of the last meal (one a day each).
var _fished_day := -1
var _cooked_day := -1


func run(runner: Node) -> void:
	t = runner
	Simulation.auto_advance = false
	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	app.start_new_game()
	await _settle()
	WindField.get_default().test_override = Callable()  # the real wind and weather
	WeatherModel.get_default().clear_cache()
	var state := GameSession.get_state_snapshot()
	state.wind_seed = SEED
	GameSession.replace_state(state)
	Simulation.passage_interrupted.connect(_on_interrupted)
	t.check_eq(GameSession.get_vessel_id(), &"arctic_wanderer_26", "[paradise] the voyage starts aboard the Arctic Wanderer 26, the smallest boat")
	var started := Time.get_ticks_msec()
	for i in LEGS.size():
		var leg: Array = LEGS[i]
		if not await _sail_leg(i, leg[0], leg[1]):
			break
		if i == 0:
			await _ashore_in(leg[1], "the first intermediate harbour")
	var arrived := GameSession.get_location_id() == &"papeete" and not GameSession.is_underway()
	t.check(arrived, "[paradise] the Arctic Wanderer arrives in Papeete, Tahiti (%d ms of simulation)" % (Time.get_ticks_msec() - started))
	if arrived:
		await _ashore_in(&"papeete", "Tahiti")
	t.check(_regions_seen.has("denmark") and _regions_seen.has("europe") and _regions_seen.has("world"),
		"[paradise] the voyage passed through the detailed Danish chart, Europe and the world chart (%s)" % [_regions_seen.keys()])
	t.check(_bites > 0 and _meals > 0, "[paradise] on the way: %d fish landed, %d meals cooked from the catch" % [_bites, _meals])
	t.check(_dateline_ok, "[paradise] the boat never jumped across the chart (positions continuous, also at the Date Line)")
	t.check(GameSession.get_rescue_count() == 0, "[paradise] no rescue was needed on the way")
	print("    (Long Passage interruptions: %s; renown %d)" % [_interruptions, GameSession.get_lifetime_renown()])
	Simulation.passage_interrupted.disconnect(_on_interrupted)
	Simulation.auto_advance = true
	app.queue_free()
	await t.frames(2)
	GameSession.end_session()
	t.use_calm_wind()


func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)


func _on_interrupted(reason: StringName, _text: String) -> void:
	_interruptions[String(reason)] = int(_interruptions.get(String(reason), 0)) + 1


## One passage: stores, fuel, readiness, depart, Long Passage time to arrival.
func _sail_leg(index: int, from: StringName, to: StringName) -> bool:
	var name := "%s -> %s" % [PortCatalog.get_default().get_display_name(from), PortCatalog.get_default().get_display_name(to)]
	app.modals.clear()
	var stock := GameSession.buy_provisions(GameSession.get_passage_store_days())
	t.check(stock == "" or stock == "Food and water are already full.",
		"[paradise] %s: stocked up for the passage (%s, %s aboard)" % [name, stock if stock else "bought", Provisions.format_days(GameSession.get_provisions().endurance_days())])
	if GameSession.get_fishing().get_lure_count("spoon") <= 0:
		GameSession.buy_lure("spoon")
	# I027: a full tank for the calms, as a skipper fills up before a passage.
	GameSession.buy_fuel()
	var plan := GameSession.plan_route_to(to)
	if not t.check(plan == "", "[paradise] %s: course plotted (%s)" % [name, plan]):
		return false
	var route := GameSession.get_planned_route()
	var readiness := PassageReadiness.assess(route.path)
	print("    %s: %d nm, about %s; readiness: %s" % [name, roundi(route.get_distance_nm()), Simulation.format_duration(float(readiness.hours) * 3600.0),
		PassageReadiness.describe(readiness).replace("\n", " ")])
	if float(readiness.hours) > PassageReadiness.FORECAST_HOURS:
		t.check(PassageReadiness.describe(readiness, 8).contains("not yet known"),
			"[paradise] %s: the readiness says honestly that the forecast does not reach the whole passage" % name)
	var depart := GameSession.depart()
	if not t.check(depart == "", "[paradise] %s: departs (readiness is advice, never a gate) %s" % [name, depart]):
		return false
	var departed_at := GameSession.get_game_time()
	var saved_midway := false
	var guard := 0
	var last := GameSession.get_vessel_position()
	while GameSession.is_underway() and guard < 200000:
		guard += 1
		if not Simulation.is_passage_running():
			Simulation.start_passage(RATE)
		Simulation.tick(TICK)
		var here := GameSession.get_vessel_position()
		if absf(here.x - last.x) > 180.0 and absf(GeoMath.wrap_delta(last.x, here.x)) > 20.0:
			_dateline_ok = false
		last = here
		var router := SeaRouter.get_loaded()
		if router:
			var region := router.grid.grid_at(here).region_id
			_regions_seen[region if region != "" else "world"] = true
		_life_aboard()
		if index == 1 and not saved_midway and GameSession.get_voyage_remaining_nm() < GameSession.get_voyage_total_nm() * 0.5:
			saved_midway = true
			await _save_and_reload_mid_ocean(name)
		if GameSession.get_rescue_count() > 0:
			break
	Simulation.stop_passage()
	var days := (GameSession.get_game_time() - departed_at) / 86400.0
	var ok := GameSession.get_location_id() == to and not GameSession.is_underway()
	t.check(ok, "[paradise] %s: arrived after %.1f days at sea, %s left aboard, hull %d %%" % [name, days,
		Provisions.format_days(GameSession.get_provisions().endurance_days()), roundi(GameSession.get_condition())])
	t.check(GameSession.get_provisions().endurance_days() > 0.0, "[paradise] %s: the stores lasted the passage" % name)
	return ok


## Life aboard the way a captain might live it: once a day the line goes
## out until a fish is landed (then it comes in), and once a day the catch
## is cooked when the stove can be used.
func _life_aboard() -> void:
	var day := floori(GameSession.get_game_time() / 86400.0)
	var fishing := GameSession.get_fishing()
	if not GameSession.get_pending_bite().is_empty():
		var result := GameSession.finish_fight(true)
		if result.get("landed", false):
			_bites += 1
		GameSession.set_line(false)
	elif not fishing.line_out and day != _fished_day and GameSession.fishing_refusal("spoon") == "":
		_fished_day = day
		GameSession.set_line(true, "spoon")
	if day != _cooked_day and not fishing.hold.is_empty() and GameSession.cooking_refusal() == "" \
			and GameSession.recipe_refusal("pan_fried_fish") == "":
		var meal := GameSession.cook("pan_fried_fish")
		if meal.error == "":
			_cooked_day = day
			_meals += 1
			Simulation.spend_time_aboard(float(meal.minutes))


## Saves in the middle of the Atlantic, loads it again: the same position,
## progress, stores and renown, and the voyage goes on.
func _save_and_reload_mid_ocean(name: String) -> void:
	Simulation.stop_passage()
	var before := GameSession.get_state_snapshot()
	var position := GameSession.get_vessel_position()
	var progress := GameSession.get_voyage_progress_nm()
	var renown := GameSession.get_lifetime_renown()
	t.check(SaveManager.save_to_slot(3, GameSession.get_state_snapshot()) == OK, "[paradise] %s: saved in mid-ocean at %s" % [name, GeoMath.format_position(position)])
	GameSession.end_session()
	var loaded := SaveManager.load_from_slot(3)
	if not t.check(loaded.is_ok(), "[paradise] %s: the mid-ocean save loads (%s)" % [name, loaded.error if not loaded.is_ok() else "ok"]):
		GameSession.replace_state(before)
		return
	GameSession.replace_state(loaded.state)
	t.check(GameSession.is_underway() and GameSession.get_vessel_position().distance_to(position) < 1e-4
		and absf(GameSession.get_voyage_progress_nm() - progress) < 1e-6,
		"[paradise] %s: after loading the boat is where it was, %d nm along, still underway" % [name, roundi(progress)])
	t.check_eq(GameSession.get_lifetime_renown(), renown, "[paradise] %s: no renown gained or lost by loading" % name)
	SaveManager.delete_slot(3)


## Moored in harbour: the gangplank is out on deck, and Go Ashore offers a
## moment there.
func _ashore_in(port_id: StringName, what: String) -> void:
	var name := PortCatalog.get_default().get_display_name(port_id)
	app.modals.clear()
	GameSession.enter_boat_area(DECK, &"from_boatyard")
	app._show_current_boat_area()
	await _settle()
	var deck := app.router.current_screen as BoatArea
	var shore := deck.get_shore_access() if deck else null
	t.check(GameSession.is_moored_in_harbour() and shore != null and shore.is_active(),
		"[paradise] %s (%s): moored, the gangplank is out" % [name, what])
	var offer := GameSession.get_shore_event()
	var event: Dictionary = offer.get("event", {})
	if t.check(not event.is_empty(), "[paradise] %s: Go Ashore offers a moment (%s)" % [name, event.get("title", "none")]):
		var result := GameSession.apply_shore_choice(event.id, 0)
		if result.error == "":
			Simulation.spend_time_ashore(float(result.minutes))
		t.check(result.error == "", "[paradise] %s: ashore: %s" % [name, result.outcome if result.error == "" else result.error])
	await t.screenshot("16_paradise_%s" % port_id)
