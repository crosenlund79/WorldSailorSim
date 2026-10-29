class_name PassagePlan
extends RefCounted
## A passage plan (Between Horizons, I027 Tier 4): a real chartplotter
## course as structured, persistent data - the contract I028's passage offers
## are built on. Navigation stays authoritative in the chartplotter: a plan is
## made from a planned route (from_route) and describes it; it never plans or
## changes a course itself.
##
## It holds the origin and destination, the waypoints and legs, the distance,
## a departure window and the estimated arrival (the simulation's own
## estimate), the sailing assumptions behind it, the likely engine use and
## fuel with its cost, the other running costs (food and water for the
## passage, the destination's dues per night), the boat and what it offers
## guests (Accommodation), and whether the passage is feasible for it, with
## the reasons when not. to_dict / from_dict keep it, versioned, so a plan
## survives a save or a hand-over unchanged.

const VERSION := 1
## Feasibility issues (ids; the texts come from describe_issue).
const ISSUE_NO_ROUTE := "no_route"
const ISSUE_STORES := "stores"
const ISSUE_SUITABILITY := "suitability"
## A passage counts as offshore or ocean by its length and its longest leg in
## open water (nm), and longer than a week is an ocean passage.
const OFFSHORE_NM := 60.0
const OCEAN_NM := 600.0

var version := VERSION
var created_at := 0.0
var origin_port_id := ""
var destination_port_id := ""
## [{"lon", "lat", "anchorage"}]
var waypoints: Array[Dictionary] = []
## [{"from": {"lon", "lat"}, "to": {"lon", "lat"}, "nm", "bearing"}]
var legs: Array[Dictionary] = []
var distance_nm := 0.0
var depart_earliest := 0.0
var depart_latest := 0.0
var estimated_seconds := 0.0
var estimated_arrival := 0.0
## What the estimate assumed: {"vessel", "wind_seed", "forecast_hours",
## "engine_start_below_kn", "engine_speed_kn", "motor_upwind", "fuel_aboard_l",
## "difficulty"}.
var assumptions := {}
var engine_hours := 0.0
var engine_nm := 0.0
var fuel_l := 0.0
var fuel_cost := 0
var provisions_cost := 0
var dues_per_night := 0
## Fuel and food and water for the passage (euros, after the difficulty).
var operating_cost := 0
## The boat: {"vessel", "name", "size_class", "comfort", "safe_guests",
## "overnight_guests", "private_guest_cabins", "skipper_privacy", "suited_to",
## "passage_stores_days"}.
var boat := {}
## {"ok": bool, "kind": coastal/offshore/ocean, "issues": [ids]}
var feasibility := {"ok": false, "kind": "coastal", "issues": []}


## A plan for the active game's planned `route`, departing from `depart_at`
## (now by default) within `window_hours`.
static func from_route(route: PlannedRoute, depart_at := -1.0, window_hours := 24.0) -> PassagePlan:
	var plan := PassagePlan.new()
	var now := GameSession.get_game_time()
	plan.created_at = now
	plan.depart_earliest = now if depart_at < 0.0 else depart_at
	plan.depart_latest = plan.depart_earliest + window_hours * 3600.0
	var vessel := GameSession.get_vessel_definition()
	var profile := GameSession.get_vessel_profile()
	var vessel_id := GameSession.get_vessel_id()
	plan.boat = {"vessel": String(vessel_id), "name": vessel.display_name, "size_class": String(Accommodation.size_class(vessel_id)),
		"comfort": String(Accommodation.comfort_tier(vessel_id)), "safe_guests": Accommodation.safe_guest_count(vessel_id),
		"overnight_guests": Accommodation.overnight_guest_count(vessel_id), "private_guest_cabins": Accommodation.private_guest_cabins(vessel_id),
		"skipper_privacy": Accommodation.skipper_has_privacy(vessel_id), "suited_to": String(Accommodation.passage_suitability(vessel_id)),
		"passage_stores_days": GameSession.get_passage_store_days()}
	plan.assumptions = {"vessel": String(vessel_id), "wind_seed": GameSession.get_wind_seed(), "forecast_hours": PassageReadiness.FORECAST_HOURS,
		"engine_start_below_kn": profile.engine_start_below_kn, "engine_speed_kn": profile.engine_speed_kn,
		"motor_upwind": GameSession.is_motoring_upwind(), "fuel_aboard_l": snappedf(GameSession.get_fuel_l(), 0.1),
		"difficulty": String(GameSession.get_difficulty())}
	if route == null or not route.has_path():
		plan.feasibility = {"ok": false, "kind": "coastal", "issues": [ISSUE_NO_ROUTE]}
		return plan
	plan.origin_port_id = String(route.origin_port_id)
	plan.destination_port_id = String(route.destination_port_id)
	for i in route.waypoints.size():
		plan.waypoints.append({"lon": route.waypoints[i].x, "lat": route.waypoints[i].y, "anchorage": route.is_anchorage(i)})
	var longest_leg := 0.0
	for leg_range in route.get_leg_ranges():
		var piece := route.path.slice(leg_range.x, leg_range.y + 1)
		var a := route.path[leg_range.x]
		var b := route.path[leg_range.y]
		var nm := GeoMath.path_length_nm(piece)
		longest_leg = maxf(longest_leg, nm)
		plan.legs.append({"from": {"lon": a.x, "lat": a.y}, "to": {"lon": b.x, "lat": b.y}, "nm": snappedf(nm, 0.1),
			"bearing": snappedf(GeoMath.rhumb_bearing(a, b), 0.1)})
	plan.distance_nm = snappedf(route.get_distance_nm(), 0.1)
	var estimate := Simulation.estimate_route(route.path, 0.0, plan.depart_earliest)
	plan.estimated_seconds = float(estimate.seconds)
	plan.estimated_arrival = plan.depart_earliest + plan.estimated_seconds
	plan.engine_hours = snappedf(float(estimate.engine_seconds) / 3600.0, 0.1)
	plan.engine_nm = snappedf(float(estimate.engine_nm), 0.1)
	plan.fuel_l = snappedf(float(estimate.fuel_l), 0.1)
	var origin := StringName(plan.origin_port_id)
	plan.fuel_cost = ceili(plan.fuel_l * Economy.fuel_price_per_litre(origin) * Difficulty.factor("costs") - 1e-6) if origin != &"" else 0
	var days := plan.estimated_seconds / 86400.0
	plan.provisions_cost = ceili(days * 2.0 * GameSession.PROVISIONS_PRICE_PER_DAY * Difficulty.factor("costs") - 1e-6)
	plan.dues_per_night = ceili(Economy.dues_per_night(StringName(plan.destination_port_id), profile.length_ft) * Difficulty.factor("costs") - 1e-6)
	plan.operating_cost = plan.fuel_cost + plan.provisions_cost
	# Feasibility: the stores the boat can carry, and the kind of passage it is fitted for.
	var kind := Accommodation.PASSAGE_COASTAL
	if plan.distance_nm >= OCEAN_NM or longest_leg >= OCEAN_NM or days > 7.0:
		kind = Accommodation.PASSAGE_OCEAN
	elif plan.distance_nm >= OFFSHORE_NM or longest_leg >= OFFSHORE_NM:
		kind = Accommodation.PASSAGE_OFFSHORE
	var issues: Array[String] = []
	if days + PassageReadiness.STORES_MARGIN_DAYS > float(plan.boat.passage_stores_days):
		issues.append(ISSUE_STORES)
	if not Accommodation.suits_passage(vessel_id, kind):
		issues.append(ISSUE_SUITABILITY)
	plan.feasibility = {"ok": issues.is_empty(), "kind": String(kind), "issues": issues}
	return plan


static func describe_issue(issue: String) -> String:
	match issue:
		ISSUE_NO_ROUTE:
			return Loc.t("No course is plotted.")
		ISSUE_STORES:
			return Loc.t("Longer than the boat can stow food and water for.")
		ISSUE_SUITABILITY:
			return Loc.t("A longer passage than the boat is fitted for.")
	return issue


func to_dict() -> Dictionary:
	return {"version": version, "created_at": created_at, "origin": origin_port_id, "destination": destination_port_id,
		"waypoints": waypoints.duplicate(true), "legs": legs.duplicate(true), "distance_nm": distance_nm,
		"depart_window": {"earliest": depart_earliest, "latest": depart_latest},
		"estimate": {"seconds": estimated_seconds, "arrival": estimated_arrival, "engine_hours": engine_hours, "engine_nm": engine_nm, "fuel_l": fuel_l},
		"assumptions": assumptions.duplicate(true),
		"costs": {"fuel": fuel_cost, "provisions": provisions_cost, "dues_per_night": dues_per_night, "operating": operating_cost},
		"boat": boat.duplicate(true), "feasibility": feasibility.duplicate(true)}


## A plan from saved data, leniently (missing parts take their defaults);
## null when it is not a plan at all or from a newer version.
static func from_dict(data: Variant) -> PassagePlan:
	if not data is Dictionary or int((data as Dictionary).get("version", 0)) < 1 or int(data.get("version", 0)) > VERSION:
		return null
	var plan := PassagePlan.new()
	plan.created_at = _num(data.get("created_at"))
	plan.origin_port_id = str(data.get("origin", ""))
	plan.destination_port_id = str(data.get("destination", ""))
	for w: Variant in data.get("waypoints", []):
		if w is Dictionary:
			plan.waypoints.append({"lon": _num(w.get("lon")), "lat": _num(w.get("lat")), "anchorage": w.get("anchorage", false) == true})
	for leg: Variant in data.get("legs", []):
		if leg is Dictionary:
			plan.legs.append((leg as Dictionary).duplicate(true))
	plan.distance_nm = _num(data.get("distance_nm"))
	var window: Dictionary = data.get("depart_window", {}) if data.get("depart_window") is Dictionary else {}
	plan.depart_earliest = _num(window.get("earliest"))
	plan.depart_latest = _num(window.get("latest"))
	var estimate: Dictionary = data.get("estimate", {}) if data.get("estimate") is Dictionary else {}
	plan.estimated_seconds = _num(estimate.get("seconds"))
	plan.estimated_arrival = _num(estimate.get("arrival"))
	plan.engine_hours = _num(estimate.get("engine_hours"))
	plan.engine_nm = _num(estimate.get("engine_nm"))
	plan.fuel_l = _num(estimate.get("fuel_l"))
	plan.assumptions = (data.get("assumptions", {}) as Dictionary).duplicate(true) if data.get("assumptions") is Dictionary else {}
	var costs: Dictionary = data.get("costs", {}) if data.get("costs") is Dictionary else {}
	plan.fuel_cost = int(_num(costs.get("fuel")))
	plan.provisions_cost = int(_num(costs.get("provisions")))
	plan.dues_per_night = int(_num(costs.get("dues_per_night")))
	plan.operating_cost = int(_num(costs.get("operating")))
	plan.boat = (data.get("boat", {}) as Dictionary).duplicate(true) if data.get("boat") is Dictionary else {}
	# Counts are whole numbers again (JSON brings every number back as a float).
	for key in ["safe_guests", "overnight_guests", "private_guest_cabins"]:
		if plan.boat.has(key):
			plan.boat[key] = int(_num(plan.boat[key]))
	if plan.assumptions.has("wind_seed"):
		plan.assumptions["wind_seed"] = int(_num(plan.assumptions["wind_seed"]))
	if data.get("feasibility") is Dictionary:
		plan.feasibility = (data.feasibility as Dictionary).duplicate(true)
	return plan


static func _num(v: Variant) -> float:
	return float(v) if (v is int or v is float) and is_finite(float(v)) else 0.0
