extends RefCounted
## I027 Tier 4, the passage-plan contract: a plan made from the chartplotter's
## course (Copenhagen to Kiel) holds its origin, destination, legs and
## distance, the departure window and the simulation's own ETA, the sailing
## assumptions, engine use, fuel and its cost, the running costs, the boat and
## its accommodation, and its feasibility; it changes nothing (the course
## stays the chartplotter's); it survives a JSON round trip; an ocean passage
## is not feasible for the 26 ft but is for the Wing 33; no course, no plan.

var t: Node


func run(runner: Node) -> void:
	t = runner
	Simulation.auto_advance = false
	_test_kiel()
	_test_round_trip()
	_test_ocean()
	t.use_calm_wind()
	GameSession.end_session()


func _moor(port: StringName, vessel_id: StringName) -> void:
	GameSession.start_new_session()
	var state := GameSession.get_state_snapshot()
	state.vessel_id = vessel_id
	state.wind_seed = 16
	state.location_id = port
	state.vessel_position = PortCatalog.get_default().get_port(port).get_geo_position()
	GameSession.replace_state(state)


func _test_kiel() -> void:
	_moor(&"copenhagen", &"arctic_wanderer_26")
	t.set_wind(270.0, 12.0)
	var none := PassagePlan.from_route(null)
	t.check(not bool(none.feasibility.ok) and PassagePlan.ISSUE_NO_ROUTE in none.feasibility.issues, "[plan] no course plotted: no plan")
	GameSession.plan_route_to(&"kiel")
	var route := GameSession.get_planned_route()
	var before := route.to_dict()
	var plan := PassagePlan.from_route(route)
	var legs_nm := 0.0
	for leg in plan.legs:
		legs_nm += float(leg.nm)
	t.check(plan.origin_port_id == "copenhagen" and plan.destination_port_id == "kiel" and plan.legs.size() == route.waypoints.size() + 1
		and absf(legs_nm - plan.distance_nm) < 1.0 and plan.distance_nm > 100.0,
		"[plan] Copenhagen -> Kiel: origin, destination, %d legs adding up to %.1f nm" % [plan.legs.size(), plan.distance_nm])
	t.check(is_equal_approx(plan.estimated_arrival - plan.depart_earliest, Simulation.estimate_route_seconds(route.path, 0.0, plan.depart_earliest))
		and plan.depart_latest - plan.depart_earliest == 24.0 * 3600.0,
		"[plan] the ETA is the simulation's own (%s), the departure window a day" % Simulation.format_duration(plan.estimated_seconds))
	t.check(plan.assumptions.vessel == "arctic_wanderer_26" and plan.assumptions.has("wind_seed") and plan.assumptions.has("fuel_aboard_l")
		and plan.assumptions.engine_speed_kn == 5.0, "[plan] the sailing assumptions are written down")
	t.check(plan.fuel_l >= 0.0 and plan.engine_hours >= 0.0 and plan.fuel_cost >= 0 and plan.provisions_cost > 0 and plan.dues_per_night > 0
		and plan.operating_cost == plan.fuel_cost + plan.provisions_cost,
		"[plan] engine %.1f h, %.1f L of fuel (€%d), food and water €%d, dues in Kiel €%d a night" % [plan.engine_hours, plan.fuel_l,
			plan.fuel_cost, plan.provisions_cost, plan.dues_per_night])
	t.check(plan.boat.safe_guests == 3 and plan.boat.overnight_guests == 2 and plan.boat.private_guest_cabins == 0 and plan.boat.suited_to == "offshore",
		"[plan] the boat and what it offers guests (Accommodation)")
	t.check(bool(plan.feasibility.ok) and plan.feasibility.kind == "offshore", "[plan] a feasible offshore passage for the 26 ft (%s)" % [plan.feasibility])
	t.check(GameSession.get_planned_route().to_dict() == before, "[plan] making a plan leaves the chartplotter's course as it was")


func _test_round_trip() -> void:
	_moor(&"copenhagen", &"arctic_wanderer_26")
	GameSession.plan_route_to(&"gothenburg")
	var plan := PassagePlan.from_route(GameSession.get_planned_route())
	var back := PassagePlan.from_dict(JSON.parse_string(JSON.stringify(plan.to_dict())))
	var same := back != null and JSON.stringify(back.to_dict()) == JSON.stringify(plan.to_dict())
	if not same and back != null:
		for key: String in plan.to_dict():
			if JSON.stringify(back.to_dict()[key]) != JSON.stringify(plan.to_dict()[key]):
				print("    differs: %s: %s vs %s" % [key, JSON.stringify(back.to_dict()[key]).left(200), JSON.stringify(plan.to_dict()[key]).left(200)])
	t.check(same, "[plan] a plan survives a JSON round trip unchanged")
	var newer := plan.to_dict()
	newer.version = PassagePlan.VERSION + 1
	t.check(PassagePlan.from_dict(newer) == null and PassagePlan.from_dict("nonsense") == null, "[plan] a newer or broken plan is refused, never misread")


func _test_ocean() -> void:
	WindField.get_default().test_override = Callable()
	WeatherModel.get_default().clear_cache()
	_moor(&"puerto_ayora", &"arctic_wanderer_26")
	GameSession.plan_route_to(&"taiohae")
	var small := PassagePlan.from_route(GameSession.get_planned_route())
	_moor(&"puerto_ayora", &"starling_33")
	GameSession.plan_route_to(&"taiohae")
	var wing := PassagePlan.from_route(GameSession.get_planned_route())
	t.check(small.feasibility.kind == "ocean" and PassagePlan.ISSUE_SUITABILITY in small.feasibility.issues and bool(wing.feasibility.ok),
		"[plan] Galápagos -> Marquesas: an ocean passage, beyond the 26 ft (%s) but feasible for the Wing 33 (%s)" % [
			small.feasibility.issues, wing.feasibility.issues])
	t.check(not PassagePlan.describe_issue(PassagePlan.ISSUE_SUITABILITY).is_empty(), "[plan] each issue has words")
