extends RefCounted
## Iteration 14: boat care. Slow, predictable wear by area (the bottom with
## the days in the water, the rig with the miles and the wind, the engine with
## its hours); boatyard services that only appear where they apply, cost and
## take time in proportion to the work and the boat; the haul-out as a small
## event; equipment upgrades with real effects; Passage Readiness as advice
## that never stops a departure; the format 11 → 12 migration; and the panels
## a player sees.

const APP_SCENE := preload("res://src/app/app.tscn")
const HOUR := 3600.0
const DAY := 86400.0

var t: Node
var app: Node


func run(runner: Node) -> void:
	t = runner
	Simulation.auto_advance = false
	t.use_calm_wind()
	_test_catalogue()
	_test_wear()
	_test_services()
	_test_upgrades()
	_test_readiness()
	_test_migration()
	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	app.start_new_game()
	await _settle()
	await _test_boatyard_ui()
	await _test_haul_out_ui()
	await _test_small_harbour_ui()
	await _test_log_and_readiness_ui()
	Simulation.auto_advance = true
	app.queue_free()
	await t.frames(2)
	GameSession.end_session()
	t.use_calm_wind()


func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)


## Puts the game in `port_id`, moored (a harbour change without sailing).
func _moor_in(port_id: StringName) -> void:
	var state := GameSession.get_state_snapshot()
	state.location_id = port_id
	state.vessel_status = SessionState.STATUS_MOORED
	state.vessel_position = PortCatalog.get_default().get_port(port_id).get_geo_position()
	state.planned_route = null
	GameSession.replace_state(state)


func _sail(hours: float, wind_kn: float) -> float:
	var before := GameSession.get_total_nm_sailed()
	t.set_wind(200.0, wind_kn)
	GameSession.plan_route_to(&"kiel")
	GameSession.depart()
	Simulation.advance(hours * HOUR)
	return GameSession.get_total_nm_sailed() - before


# --- Model ------------------------------------------------------------------------------

func _test_catalogue() -> void:
	var upgrades := BoatCare.get_upgrades()
	t.check(upgrades.size() >= 4 and upgrades.size() <= 8, "[catalogue] %d equipment upgrades (four to eight)" % upgrades.size())
	var ids := upgrades.map(func(u: Dictionary) -> String: return String(u.id))
	t.check(ids.all(func(id: String) -> bool: return BoatCare.upgrade_price(id, 26.0) < BoatCare.upgrade_price(id, 40.0)),
		"[catalogue] bigger boats need bigger (dearer) gear")
	t.check(BoatCare.upgrade_price("stainless_rigging", 40.0) <= 1500, "[catalogue] the dearest fitting stays modest (%s for a 40 ft boat)" %
		GameSession.format_money(BoatCare.upgrade_price("stainless_rigging", 40.0)))


func _test_wear() -> void:
	GameSession.start_new_session()
	var start := GameSession.get_boat_care()
	t.check(start.rig_wear == 0.0 and start.engine_hours == 0.0 and start.upgrades.is_empty(), "[wear] a new game starts with a fresh boat")
	for area in BoatCare.AREAS:
		t.check(GameSession.get_care_level(area) == BoatCare.LEVEL_GOOD, "[wear] %s: good at the start" % BoatCare.AREA_NAMES[area])
	# The bottom: one point of growth a day in the water.
	Simulation.advance(30.0 * DAY)
	var care := GameSession.get_boat_care()
	t.check(is_equal_approx(BoatCare.fouling(care, GameSession.get_game_time()), 30.0), "[wear] a month in the water: some weed (%.0f)" %
		BoatCare.fouling(care, GameSession.get_game_time()))
	t.check(GameSession.get_care_level(BoatCare.AREA_HULL) == BoatCare.LEVEL_COSMETIC, "[wear] after a month the bottom is cosmetic, nothing urgent")
	var base := GameSession.get_base_vessel_profile()
	t.check(is_equal_approx(GameSession.get_vessel_profile().max_sail_speed_kn, base.max_sail_speed_kn),
		"[wear] no speed lost yet at 30 days")
	Simulation.advance(45.0 * DAY)
	var loss := 1.0 - GameSession.get_vessel_profile().max_sail_speed_kn / base.max_sail_speed_kn
	t.check(loss > 0.0 and loss <= BoatCare.FOULING_MAX_LOSS + 1e-6, "[wear] 75 days: weed costs a little speed (%.1f %%)" % (loss * 100.0))
	t.check(GameSession.get_care_level(BoatCare.AREA_HULL) == BoatCare.LEVEL_RECOMMENDED, "[wear] after 75 days a haul-out is recommended")
	# The rig wears with the miles, faster in a strong breeze.
	GameSession.start_new_session()
	var nm := _sail(6.0, 12.0)
	var light := GameSession.get_boat_care().rig_wear
	t.check(nm > 10.0 and light > 0.0 and light < nm * BoatCare.RIG_WEAR_PER_NM * 1.01 + 0.01,
		"[wear] %.0f nm in a moderate breeze: rig wear %.2f (slow)" % [nm, light])
	GameSession.start_new_session()
	var fresh_nm := _sail(6.0, 24.0)
	var fresh := GameSession.get_boat_care().rig_wear
	t.check(fresh / maxf(fresh_nm, 0.1) > light / maxf(nm, 0.1) * 1.5, "[wear] a fresh breeze wears the rig faster per mile (%.3f vs %.3f per nm)" % [
		fresh / maxf(fresh_nm, 0.1), light / maxf(nm, 0.1)])
	# The engine counts its hours under power.
	GameSession.start_new_session()
	_sail(4.0, 1.0)
	var hours := GameSession.get_boat_care().engine_hours
	t.check(hours > 2.0 and hours <= 4.01, "[wear] four hours of calm under engine: %.1f engine hours" % hours)
	# Predictable: the same sailing gives the same wear.
	GameSession.start_new_session()
	_sail(6.0, 12.0)
	t.check(is_equal_approx(GameSession.get_boat_care().rig_wear, light), "[wear] the same passage wears the same (predictable)")
	GameSession.end_session()


func _test_services() -> void:
	GameSession.start_new_session()
	# Lohals: no boatyard, so no service and no charge.
	_moor_in(&"lohals")
	DevTools.set_condition(60.0)
	var funds := GameSession.get_funds()
	t.check(GameSession.perform_service(BoatCare.SERVICE_REPAIR).error.contains("no boatyard") and GameSession.get_funds() == funds,
		"[yard] Lohals: no boatyard work, nothing charged")
	# Korsør: a boatyard, but no haul-out.
	_moor_in(&"korsor")
	t.check(GameSession.service_refusal(BoatCare.SERVICE_REPAIR) == "", "[yard] Korsør repairs")
	t.check(GameSession.service_refusal(BoatCare.SERVICE_HAUL_OUT) != "" and GameSession.haul_out().error != "" and GameSession.get_funds() == funds,
		"[yard] Korsør cannot haul out, and charges nothing for asking")
	# Costs scale with the damage and the boat.
	var small := GameSession.service_quote(BoatCare.SERVICE_REPAIR)
	DevTools.set_condition(20.0)
	var big_damage := GameSession.service_quote(BoatCare.SERVICE_REPAIR)
	t.check(int(big_damage.cost) > int(small.cost) and float(big_damage.minutes) > float(small.minutes),
		"[yard] more damage costs more and takes longer (%s → %s)" % [small, big_damage])
	t.board(&"halcyon_40")
	DevTools.set_condition(20.0)
	var big_boat := GameSession.service_quote(BoatCare.SERVICE_REPAIR)
	t.check(int(big_boat.cost) > int(big_damage.cost), "[yard] a bigger boat costs more to repair (%s vs %s)" % [big_boat.cost, big_damage.cost])
	t.check(GameSession.service_refusal(BoatCare.SERVICE_ENGINE) != "" and GameSession.service_refusal(BoatCare.SERVICE_RIG) != "",
		"[yard] services that are not needed are not sold")
	# Copenhagen hauls out: bottom cleaned and hull repaired in one, for a day.
	_moor_in(&"copenhagen")
	Simulation.advance(60.0 * DAY)
	funds = GameSession.get_funds()
	var quote := GameSession.haul_out_quote([])
	var result := GameSession.haul_out()
	var care := GameSession.get_boat_care()
	t.check(result.error == "" and GameSession.get_funds() == funds - int(quote.cost) and is_equal_approx(float(result.minutes), 24.0 * 60.0),
		"[haul-out] Copenhagen: %s, a day (%s)" % [GameSession.format_money(int(quote.cost)), result])
	t.check(BoatCare.fouling(care, GameSession.get_game_time()) < 0.01 and is_equal_approx(GameSession.get_condition(), 100.0),
		"[haul-out] the bottom is clean and the hull repaired")
	t.check(result.first and GameSession.get_objective_progress().is_completed(&"care:first_haul_out"), "[haul-out] the first one is noted (+2 renown)")
	t.check(care.history.size() == 1 and care.history[0].kind == "haul_out", "[haul-out] it is written in the boat's care history")
	t.check(GameSession.get_aboard_moments().any(func(m: Dictionary) -> bool: return String(m.text).contains("haul-out")),
		"[haul-out] and among the Captain's Log moments")
	var again := GameSession.haul_out()
	t.check(again.error == "" and not again.first, "[haul-out] another haul-out is fine but not noted again")
	GameSession.end_session()


func _test_upgrades() -> void:
	GameSession.start_new_session()
	t.check(GameSession.get_cool_box_capacity() == 6 and GameSession.get_calm_cooking_wind_kn() == 18.0
		and GameSession.get_anchor_holding_bonus_kn() == 0.0 and GameSession.get_warning_horizon_hours() == 6.0,
		"[upgrades] standard equipment: 6 fish, cooking to 18 kn, no extra holding, warnings 6 h ahead")
	var funds := GameSession.get_funds()
	var spent := 0
	for id in ["large_cool_box", "gimballed_stove", "heavy_anchor", "weather_receiver", "stainless_rigging"]:
		var result := GameSession.install_upgrade(id)
		t.check(result.error == "", "[upgrades] %s fitted in Copenhagen (%s)" % [id, result])
		spent += int(result.cost)
	t.check(GameSession.get_funds() == funds - spent, "[upgrades] paid once each (%s)" % GameSession.format_money(spent))
	t.check(GameSession.install_upgrade("large_cool_box").error.contains("already") and GameSession.get_funds() == funds - spent,
		"[upgrades] never fitted or paid twice")
	t.check(GameSession.get_cool_box_capacity() == 10 and GameSession.get_calm_cooking_wind_kn() == 26.0
		and GameSession.get_anchor_holding_bonus_kn() == 5.0 and GameSession.get_warning_horizon_hours() == 10.0,
		"[upgrades] effects: 10 fish, cooking to 26 kn, +5 kn holding, warnings 10 h ahead")
	var calm := WindField.Sample.make(90.0, 30.0)
	t.check(AnchorSite.holding_margin(5, 0.5, AnchorSite.EXPOSED, calm) + GameSession.get_anchor_holding_bonus_kn()
		> AnchorSite.holding_margin(5, 0.5, AnchorSite.EXPOSED, calm), "[upgrades] the heavier anchor holds in more wind")
	var care := GameSession.get_boat_care()
	t.check(is_equal_approx(BoatCare.rig_wear_for(100.0, 12.0, care), BoatCare.rig_wear_for(100.0, 12.0, BoatCareState.create(0.0)) * 0.5),
		"[upgrades] stainless rigging halves the rig wear")
	# The coating needs a yard that hauls out; Korsør cannot fit it.
	_moor_in(&"korsor")
	t.check(GameSession.upgrade_refusal("hard_antifouling") != "", "[upgrades] the hard coating needs a haul-out yard")
	_moor_in(&"copenhagen")
	var result := GameSession.haul_out([&"hard_antifouling"] as Array[StringName])
	t.check(result.error == "" and GameSession.has_upgrade("hard_antifouling"), "[upgrades] applied while hauled out in Copenhagen")
	Simulation.advance(50.0 * DAY)
	t.check(BoatCare.fouling(GameSession.get_boat_care(), GameSession.get_game_time()) < 25.0,
		"[upgrades] with the coating, 50 days bring only light growth")
	# No pay-to-win: everything fitted, the boat is still the same small boat.
	var base := GameSession.get_base_vessel_profile()
	t.check(GameSession.get_vessel_profile().max_sail_speed_kn <= base.max_sail_speed_kn + 1e-6,
		"[upgrades] no upgrade makes the boat faster than new")
	GameSession.end_session()


func _test_readiness() -> void:
	GameSession.start_new_session()
	t.use_calm_wind()
	GameSession.plan_route_to(&"malmo")
	var ready := PassageReadiness.assess(GameSession.get_planned_route().path)
	t.check(ready.level == PassageReadiness.OK and String(ready.summary) == "Ready to sail.", "[readiness] a sound boat, full stores, calm: %s" % ready.summary)
	DevTools.set_condition(30.0)
	DevTools.set_provisions(0.2)
	var worried := PassageReadiness.assess(GameSession.get_planned_route().path)
	var topics: Array = worried.items.filter(func(i: Dictionary) -> bool: return int(i.level) == PassageReadiness.CONSIDER).map(func(i: Dictionary) -> String: return i.topic)
	t.check(worried.level == PassageReadiness.CONSIDER and "hull" in topics and "stores" in topics,
		"[readiness] damaged and short of stores: worth a second thought (%s)" % [topics])
	t.check(PassageReadiness.describe(worried).contains("repair") and not PassageReadiness.describe(worried).contains("cannot"),
		"[readiness] in friendly words: %s" % PassageReadiness.describe(worried).replace("\n", " / "))
	t.check(GameSession.depart() == "", "[readiness] advice only: the boat can still set sail")
	GameSession.start_new_session()
	GameSession.plan_route_to(&"reykjavik")
	var long_way := PassageReadiness.assess(GameSession.get_planned_route().path)
	t.check(long_way.items.any(func(i: Dictionary) -> bool: return i.topic == "length"),
		"[readiness] a long passage notes its length (%s)" % PassageReadiness.describe(long_way).replace("\n", " / "))
	t.check(long_way.items.any(func(i: Dictionary) -> bool: return i.topic == "boat_size"), "[readiness] the Arctic Wanderer is reminded she is small")
	DevTools.set_provisions(9.0)
	var short_stores := PassageReadiness.assess(GameSession.get_planned_route().path)
	t.check(short_stores.items.any(func(i: Dictionary) -> bool: return i.topic == "stores" and int(i.level) == PassageReadiness.CONSIDER),
		"[readiness] nine days of stores for a ten-day passage: worth a second thought")
	t.board(&"halcyon_40")
	var big := PassageReadiness.assess(GameSession.get_planned_route().path)
	t.check(not big.items.any(func(i: Dictionary) -> bool: return i.topic == "boat_size"), "[readiness] the Halcyon 40 is not called small")
	t.use_calm_wind()
	GameSession.end_session()


func _test_migration() -> void:
	GameSession.start_new_session()
	var state := GameSession.get_state_snapshot()
	state.captains_log.total_nm = 500.0
	t.check_eq(SaveManager.save_to_slot(3, state), OK, "[migration] (setup) saved")
	var path: String = SaveManager._slot_path(3)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	data.version = 11
	data.game_version = "0.101a"
	data.session.erase("boat_care")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t", true, true))
	file.close()
	var loaded := SaveManager.load_from_slot(3)
	if t.check(loaded.is_ok(), "[migration] an Iteration 13 save (format 11) loads (%s)" % loaded.error):
		var care: BoatCareState = loaded.state.get_boat_care(loaded.state.vessel_id)
		t.check(is_equal_approx(care.rig_wear, 10.0) and is_equal_approx(care.engine_hours, 15.0)
			and is_equal_approx(loaded.state.game_time - care.hull_cleaned_at, 20.0 * DAY) and care.upgrades.is_empty(),
			"[migration] its boat gets a fair starting record: 20 days in the water, rig and engine worn by its 500 nm")
		t.check(loaded.state.funds == state.funds and loaded.state.location_id == state.location_id, "[migration] nothing else changes")
	SaveManager.delete_slot(3)
	GameSession.end_session()


# --- Panels ----------------------------------------------------------------------------

func _open_boat_care() -> BoatCareMenu:
	app.modals.clear()
	GameSession.enter_boat_area(SessionState.AREA_EXTERIOR, &"from_boatyard")
	app._show_current_boat_area()
	await _settle()
	app.open_boatyard()
	await t.frames(2)
	var yard := app.modals.get_top() as BoatyardMenu
	if yard == null:
		return null
	await t.click(yard.find_child("CareButton", true, false) as Button)
	await t.frames(3)
	return app.modals.get_top() as BoatCareMenu


func _test_boatyard_ui() -> void:
	_moor_in(&"copenhagen")
	Simulation.advance(55.0 * DAY)
	DevTools.set_condition(62.0)
	DevTools.set_provisions(Provisions.CAPACITY_DAYS)
	var state := GameSession.get_state_snapshot()
	state.get_boat_care(state.vessel_id).rig_wear = 38.0
	state.get_boat_care(state.vessel_id).engine_hours = 90.0
	GameSession.replace_state(state)
	var menu := await _open_boat_care()
	if not t.check(menu != null, "[ui] Boat care opens from the Copenhagen boatyard"):
		return
	var view := menu.get_overview()
	t.check(view.get_level_text(BoatCare.AREA_HULL) == "Service recommended" and view.get_level_text(BoatCare.AREA_RIG) == "Service recommended"
		and view.get_level_text(BoatCare.AREA_ENGINE) == "Service recommended",
		"[ui] the overview reads each area in words (%s, %s, %s)" % [view.get_level_text(BoatCare.AREA_HULL),
			view.get_level_text(BoatCare.AREA_RIG), view.get_level_text(BoatCare.AREA_ENGINE)])
	t.check(menu.get_service_button(BoatCare.SERVICE_HAUL_OUT) != null, "[ui] Copenhagen offers the haul-out")
	app.toasts.clear()
	await t.screenshot("14_11_maintenance_overview")
	var screen := Rect2(Vector2.ZERO, menu.get_viewport_rect().size)
	var close := menu.find_child("CloseButton", true, false) as Control
	t.check(screen.encloses(close.get_global_rect()), "[ui] the panel fits the window")
	var funds := GameSession.get_funds()
	var time := GameSession.get_game_time()
	var quote := GameSession.service_quote(BoatCare.SERVICE_RIG)
	await t.click(menu.get_service_button(BoatCare.SERVICE_RIG))
	await t.frames(2)
	t.check(GameSession.get_funds() == funds - int(quote.cost) and GameSession.get_game_time() >= time + float(quote.minutes) * 60.0 - 1.0,
		"[ui] the rig service is paid and its time passes ashore (%s, %d min)" % [GameSession.format_money(int(quote.cost)), roundi(float(quote.minutes))])
	t.check(menu.get_service_button(BoatCare.SERVICE_RIG).disabled and view.get_level_text(BoatCare.AREA_RIG) == "Good",
		"[ui] the rig now reads good; the service is no longer offered")
	await t.click(menu.get_service_button(BoatCare.SERVICE_REPAIR))
	await t.frames(2)
	t.check(is_equal_approx(GameSession.get_condition(), 100.0), "[ui] the hull is repaired")
	app.toasts.clear()
	await t.screenshot("14_12_boatyard_repairs")
	# I020: gear sold over the counter (the cool box, the weather receiver,
	# the stove) is the chandlery's; the yard fits the heavy anchor and chain.
	t.check(menu.get_upgrade_button("large_cool_box") == null, "[ui] the cool box is the chandlery's, not the yard's")
	var cool := menu.get_upgrade_button("heavy_anchor")
	t.check(cool != null and not cool.disabled, "[ui] equipment is offered: %s" % (cool.text if cool else "-"))
	(menu.find_child("Body", true, false) as ScrollContainer).ensure_control_visible(cool)
	await t.frames(2)
	await t.click(cool)
	await t.frames(2)
	t.check(GameSession.has_upgrade("heavy_anchor") and cool.disabled and cool.text == "Fitted", "[ui] the heavy anchor is fitted")
	(menu.find_child("Body", true, false) as ScrollContainer).scroll_vertical = 10000
	await t.frames(2)
	app.toasts.clear()
	await t.screenshot("14_14_upgrades")
	menu.close()
	await t.frames(2)


func _test_haul_out_ui() -> void:
	var menu := await _open_boat_care()
	if menu == null:
		return
	await t.click(menu.get_service_button(BoatCare.SERVICE_HAUL_OUT))
	await t.frames(3)
	var panel := app.modals.get_top() as HaulOutPanel
	if not t.check(panel != null, "[ui] the haul-out panel opens"):
		return
	panel.set_option(BoatCare.SERVICE_ENGINE, true)
	await t.frames(2)
	var quote := GameSession.haul_out_quote([BoatCare.SERVICE_ENGINE] as Array[StringName])
	t.check((panel.find_child("ConfirmButton", true, false) as Button).text.contains(GameSession.format_money(int(quote.cost))),
		"[ui] the total includes the engine service done while she is out (%s)" % GameSession.format_money(int(quote.cost)))
	await t.screenshot("14_13a_haul_out_options")
	var funds := GameSession.get_funds()
	var time := GameSession.get_game_time()
	await t.click(panel.find_child("ConfirmButton", true, false) as Button)
	await t.frames(20)
	app.toasts.clear()
	await t.screenshot("14_13b_haul_out_lifting")
	await t.wait_until(func() -> bool: return panel.is_finished(), 6.0)
	panel.finish_now()
	await t.frames(3)
	t.check(panel.get_scene().lift >= 1.0 and panel.get_scene().fouled <= 0.01, "[ui] she comes up in the slings and the weed comes off")
	t.check(GameSession.get_funds() == funds - int(quote.cost) and GameSession.get_game_time() >= time + 24.0 * HOUR - 1.0,
		"[ui] paid and a day passes ashore")
	t.check(GameSession.get_boat_care().engine_hours == 0.0 and GameSession.get_care_level(BoatCare.AREA_HULL) == BoatCare.LEVEL_GOOD,
		"[ui] the bottom and the engine read good afterwards")
	app.toasts.clear()
	await t.screenshot("14_13_haul_out")
	await t.click(panel.find_child("ConfirmButton", true, false) as Button)
	await t.frames(2)
	t.check(app.modals.get_top() is BoatCareMenu, "[ui] back to Boat care")
	app.modals.clear()
	await t.frames(2)


func _test_small_harbour_ui() -> void:
	_moor_in(&"stege")
	var funds := GameSession.get_funds()
	app.modals.clear()
	GameSession.enter_boat_area(SessionState.AREA_EXTERIOR, &"start")
	app._show_current_boat_area()
	await _settle()
	t.check(app.router.current_screen is BoatArea, "[ui] Stege: aboard, moored")
	# I026: the businesses stand on the quay, each in its own building (the
	# deck is freed on the way up).
	var front := await TestQuay.go_up(t, app)
	t.check(front != null and front.get_storefront(QuayLayout.BOATYARD) == null and front.get_station(QuayLayout.BOATYARD) == null
		and front.get_station(HarbourFront.TRAVEL_LIFT) == null, "[ui] Stege, a small harbour: no boatyard on the quay")
	app.leave_quay()
	await _settle()
	app.open_boatyard()
	await t.frames(2)
	t.check(app.modals.is_empty() and app.open_boat_care() == null and GameSession.get_funds() == funds,
		"[ui] no boatyard, no boat care, nothing charged")
	app.toasts.clear()
	await t.screenshot("14_16_small_harbour_without_yard")
	_moor_in(&"korsor")
	var menu := await _open_boat_care()
	t.check(menu != null and menu.get_service_button(BoatCare.SERVICE_HAUL_OUT) == null and menu.get_upgrade_button("hard_antifouling") == null,
		"[ui] Korsør's yard shows only what it does: no haul-out, no coating")
	app.modals.clear()
	await t.frames(2)


func _test_log_and_readiness_ui() -> void:
	_moor_in(&"copenhagen")
	app.modals.clear()
	app.open_captains_log()
	await t.frames(3)
	var log := app.modals.get_top() as CaptainsLogMenu
	if t.check(log != null, "[log] the Captain's Log opens"):
		log.show_tab(CaptainsLogMenu.TAB_BOAT)
		await t.frames(2)
		t.check(log.get_current_tab_name() == "Boat", "[log] it has a Boat tab")
		var history := log.find_child("History0", true, false) as Label
		t.check(history != null and history.text.contains("Copenhagen"), "[log] the boatyard visits are listed (%s)" % (history.text if history else "-"))
		await t.screenshot("14_11b_log_boat_tab")
		log.close()
		await t.frames(2)
	# Readiness in the chart's course panel: advice, never a lock.
	DevTools.set_condition(45.0)
	DevTools.set_provisions(1.0)
	app.open_chart()
	await _settle()
	var world := app.router.current_screen as WorldMap
	if t.check(world != null, "[readiness] the chart opens"):
		var view := world.get_map_view()
		view.center_on_geo(Vector2(11.6, 55.3), 260.0 / view.units_per_degree)
		await t.frames(2)
		await t.click_at(view.get_port_screen_position(&"svendborg"))
		await t.click(world.find_child("PlotButton", true, false))
		await t.frames(3)
		var label := world.find_child("ReadinessLabel", true, false) as Label
		t.check(label.visible and label.text.begins_with("Passage readiness:") and int(world.readiness.get("level", 0)) == PassageReadiness.CONSIDER,
			"[readiness] the course panel shows it (%s)" % label.text.replace("\n", " / "))
		app.toasts.clear()
		await t.screenshot("14_15_passage_readiness")
		await t.click(world.find_child("ApplyButton", true, false))
		await t.frames(2)
		t.check(not (world.find_child("SetSailButton", true, false) as Button).disabled, "[readiness] Set sail stays available")
		app.close_chart()
		await _settle()
	DevTools.set_condition(100.0)
	DevTools.set_provisions(14.0)
