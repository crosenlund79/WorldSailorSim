class_name SessionState
extends RefCounted
## Plain-data representation of everything a game session persists.
##
## This is the explicit, serializable state that GameSession owns and that
## SaveManager writes. It contains no node references, so it exists regardless
## of which scene is visible. to_dict()/from_dict() define the save format;
## each subsystem keeps its data in its own top-level section ("boat",
## "player", "clock", "wind", "vessel", "navigation", "economy", "provisions",
## "rescue", "log", "progress", "hat") so future systems can add sections of their own.

const AREA_INTERIOR := &"interior"
const AREA_EXTERIOR := &"exterior"
const BOAT_AREAS: Array[StringName] = [AREA_INTERIOR, AREA_EXTERIOR]
const AREA_NAMES := {AREA_INTERIOR: "Cabin", AREA_EXTERIOR: "Deck"}

const STATUS_MOORED := &"moored"
const STATUS_UNDERWAY := &"underway"
const STATUS_ARRIVED := &"arrived"
const STATUSES: Array[StringName] = [STATUS_MOORED, STATUS_UNDERWAY, STATUS_ARRIVED]

const TIME_SCALES: Array[int] = [1, 5, 20]
## New games start on 1 May 2026, 08:00 UTC (start of the sailing season).
const START_TIME_ISO := "2026-05-01T08:00:00"
## Money a new game starts with (whole euros) and what a rescue at sea costs.
const STARTING_FUNDS := 10000
const RESCUE_FEE := 1000

## Boat area the player is in.
var boat_area: StringName = AREA_INTERIOR
## Player position in the boat area's local coordinates. Only meaningful when
## has_player_position is true; otherwise the area places the player at
## spawn_point (used for new games and for moving between areas).
var player_position := Vector2.ZERO
var has_player_position := false
var spawn_point: StringName = &""
## Port id where the boat lies; empty while underway.
var location_id: StringName
## The course planned from the current port, or null. Not used while underway.
var planned_route: PlannedRoute

## Authoritative game clock: seconds since the Unix epoch, UTC.
var game_time := 0.0
## Selected time acceleration (one of TIME_SCALES).
var time_scale := 1
## Simulation paused by the player (the clock stands still; UI keeps working).
## The selected time_scale is kept and used again on resuming.
var paused := false
## Moored (never left), underway, or arrived (at location_id after a voyage).
var vessel_status: StringName = STATUS_MOORED
## Vessel's geographic position Vector2(lon, lat).
var vessel_position := Vector2.ZERO
## Sail/engine state and the automatic controller's memory (used while underway).
var propulsion := PropulsionState.new()
## Sail trim (Iteration 18, SailTrim): left to the crew, or the captain's
## setting (-1 eased .. +1 sheeted in). Kept across course changes, voyages
## and saves; its effect is worked out from the wind at the time. Optional in
## a save (format 12): absent means the crew trims.
var trim_auto := true
var trim_value := 0.0
## Selects this game's deterministic weather: the wind field's variation and
## every weather event (WeatherModel). Events are a pure function of this seed
## and time, so saving the seed saves the weather.
var wind_seed := 1
## Which WeatherModel generation rules the weather follows (data/weather/
## weather_events.json "model_version"; for future compatibility checks).
var weather_model_version := 1
## The weather the boat has been in and for how long (see WeatherExposure).
var weather_exposure := WeatherExposure.new()
## Which boat the player owns (a VesselDefinition id, stable across versions).
var vessel_id: StringName = VesselCatalog.STARTER_ID
## The ship's companion (kind and resting spot in the cabin).
var companion := CompanionState.new()
## The voyage being sailed, or null when not underway.
var voyage: Voyage
## The boats the captain owns (I022; vessel ids). The one aboard is always
## among them. Saves from before I022 own every boat: they could move aboard
## any of them at a boatyard, and nothing is ever taken away.
var owned_vessels: Array[StringName] = [VesselCatalog.STARTER_ID]
## Postcards and the little game (I022; PastimesState). Older saves: none yet.
var pastimes := PastimesState.new()
## Relaxed, Standard or Seasoned Captain (I022; Difficulty). Older saves: Standard.
var difficulty: StringName = Difficulty.STANDARD
## Euros (whole). Never negative.
var funds := STARTING_FUNDS
## Food and water aboard (days).
var provisions := Provisions.new()
## Each boat's overall condition in percent, by vessel id (String). A boat
## that is not listed is in perfect condition (100), so switching boats keeps
## every boat's own damage.
var vessel_conditions := {}
## Weather damage has been applied for the voyage up to this game time, so no
## stretch of time is ever counted twice (see Simulation._assess_weather).
var damage_applied_until := 0.0
## Rescues so far, and the last one: {"time", "fee", "funds_after", "from"}.
var rescue_count := 0
var last_rescue := {}
## The Captain's Log: sailing statistics, harbours visited, recent voyages.
var captains_log := CaptainsLog.new()
## Renown and the sailing objectives completed.
var progress := ObjectiveProgress.new()
## The player's captain's hat (one at a time; it belongs to the player).
var hat := HatState.new()
## Fishing, the galley and the anchor (Iteration 13).
var fishing := FishingState.new()
var galley := GalleyState.new()
var anchor := AnchorState.new()
## Each boat's care record (Iteration 14): wear, fitted equipment, service
## history; by vessel id. A boat without one gets a fresh record on first use.
var boat_care := {}
## A boat of your own (I020): cabin things and sailcloth, per boat. Optional
## in saves (older saves: plain cabins, classic sails).
var home := HomeState.new()


static func create_new(start_location: StringName, start_area: StringName, start_spawn: StringName,
		companion_kind: StringName = CompanionState.DEFAULT_KIND, level: StringName = Difficulty.STANDARD) -> SessionState:
	var state := SessionState.new()
	state.difficulty = Difficulty.valid(level)
	state.funds = Difficulty.starting_funds(state.difficulty)
	state.owned_vessels = [state.vessel_id] as Array[StringName]
	state.location_id = start_location
	state.boat_area = start_area
	state.spawn_point = start_spawn
	state.game_time = get_start_time()
	state.weather_exposure.reset(state.game_time)
	state.damage_applied_until = state.game_time
	state.companion = CompanionState.create(companion_kind, state.game_time)
	state.captains_log = CaptainsLog.create(start_location, state.game_time)
	state.hat = HatState.create(state.game_time)
	state.fishing.checked_until = state.game_time
	state.anchor.checked_until = state.game_time
	state.get_boat_care(state.vessel_id)
	var port := PortCatalog.get_default().get_port(start_location)
	state.vessel_position = port.get_geo_position() if port else Vector2.ZERO
	return state


static func get_start_time() -> float:
	return float(Time.get_unix_time_from_datetime_string(START_TIME_ISO))


static func get_area_display_name(area: StringName) -> String:
	return Loc.t(AREA_NAMES.get(area, String(area).capitalize()))


## The owned boats from a save's "fleet" section: known ids only, the boat
## aboard always included; no section (a save from before I022) owns all.
static func owned_from(fleet: Variant, aboard: StringName) -> Array[StringName]:
	var catalog := VesselCatalog.get_default()
	var owned: Array[StringName] = []
	var saved: Variant = (fleet as Dictionary).get("owned") if fleet is Dictionary else null
	if saved is Array:
		for id: Variant in saved:
			if (id is String or id is StringName) and catalog.has_vessel(StringName(id)) and not StringName(id) in owned:
				owned.append(StringName(id))
	else:
		owned = catalog.get_ids()
	if catalog.has_vessel(aboard) and not aboard in owned:
		owned.append(aboard)
	return owned


## The owned boats as saved: always including the boat aboard (the same rule
## as owned_from, so saving and loading give back exactly the same).
func _owned_for_save() -> Array:
	var ids := owned_vessels.map(func(id: StringName) -> String: return String(id))
	if not String(vessel_id) in ids and VesselCatalog.get_default().has_vessel(vessel_id):
		ids.append(String(vessel_id))
	return ids


func duplicate_state() -> SessionState:
	var copy := SessionState.new()
	copy.boat_area = boat_area
	copy.player_position = player_position
	copy.has_player_position = has_player_position
	copy.spawn_point = spawn_point
	copy.location_id = location_id
	copy.planned_route = planned_route.duplicate_route() if planned_route else null
	copy.game_time = game_time
	copy.time_scale = time_scale
	copy.paused = paused
	copy.vessel_status = vessel_status
	copy.vessel_position = vessel_position
	copy.propulsion = propulsion.duplicate_state()
	copy.trim_auto = trim_auto
	copy.trim_value = trim_value
	copy.wind_seed = wind_seed
	copy.weather_model_version = weather_model_version
	copy.weather_exposure = weather_exposure.duplicate_exposure()
	copy.companion = companion.duplicate_state()
	copy.vessel_id = vessel_id
	copy.voyage = voyage.duplicate_voyage() if voyage else null
	copy.funds = funds
	copy.owned_vessels = owned_vessels.duplicate()
	copy.difficulty = difficulty
	copy.pastimes = pastimes.duplicate_state()
	copy.provisions = provisions.duplicate_provisions()
	copy.vessel_conditions = vessel_conditions.duplicate()
	copy.damage_applied_until = damage_applied_until
	copy.rescue_count = rescue_count
	copy.last_rescue = last_rescue.duplicate(true)
	copy.captains_log = captains_log.duplicate_log()
	copy.progress = progress.duplicate_progress()
	copy.hat = hat.duplicate_hat()
	copy.fishing = fishing.duplicate_state()
	copy.galley = galley.duplicate_state()
	copy.anchor = anchor.duplicate_state()
	for id: String in boat_care:
		copy.boat_care[id] = (boat_care[id] as BoatCareState).duplicate_state()
	copy.home = home.duplicate_home()
	return copy


## The care record of boat `id`, created fresh (bottom just cleaned, nothing
## worn) when the boat has none yet.
func get_boat_care(id: StringName) -> BoatCareState:
	if not boat_care.has(String(id)):
		boat_care[String(id)] = BoatCareState.create(game_time)
	return boat_care[String(id)]


func _boat_care_dict() -> Dictionary:
	var result := {}
	for id: String in boat_care:
		result[id] = (boat_care[id] as BoatCareState).to_dict()
	return result


## The condition (0-100 %) of boat `id`.
func get_condition(id: StringName) -> float:
	return float(vessel_conditions.get(String(id), VesselCondition.FULL))


func set_condition(id: StringName, percent: float) -> void:
	vessel_conditions[String(id)] = clampf(percent, 0.0, VesselCondition.FULL)


func to_dict() -> Dictionary:
	var player := {}
	if has_player_position:
		player["position"] = {"x": player_position.x, "y": player_position.y}
	else:
		player["spawn_point"] = String(spawn_point)
	return {
		"boat": {"area": String(boat_area)},
		"player": player,
		"clock": {"game_time": game_time, "time_scale": time_scale, "paused": paused},
		"wind": {"seed": wind_seed},
		"weather": {"model_version": weather_model_version, "exposure": weather_exposure.to_dict()},
		"companion": companion.to_dict(),
		"vessel": {
			"id": String(vessel_id),
			"status": String(vessel_status),
			"position": {"lon": vessel_position.x, "lat": vessel_position.y},
			"propulsion": propulsion.to_dict(),
			"sail_trim": {"auto": trim_auto, "value": trim_value},
			"conditions": vessel_conditions.duplicate(),
			"damage_applied_until": damage_applied_until,
		},
		"economy": {"funds": funds},
		"fleet": {"owned": _owned_for_save()},
		"difficulty": String(difficulty),
		"pastimes": pastimes.to_dict(),
		"provisions": provisions.to_dict(),
		"rescue": {"count": rescue_count, "last": last_rescue.duplicate(true)},
		"log": captains_log.to_dict(),
		"progress": progress.to_dict(),
		"hat": hat.to_dict(),
		"fishing": fishing.to_dict(),
		"galley": galley.to_dict(),
		"anchor": anchor.to_dict(),
		"boat_care": _boat_care_dict(),
		"home": home.to_dict(),
		"navigation": {
			"location_id": String(location_id),
			"planned_route": planned_route.to_dict() if planned_route else null,
			"voyage": voyage.to_dict() if voyage else null,
		},
	}


## Validates saved data and builds a complete new state from it. Returns null
## (and appends human-readable reasons to `errors`) if anything is missing or
## invalid; a partially valid state is never returned.
static func from_dict(data: Variant, errors: Array[String]) -> SessionState:
	if not data is Dictionary:
		errors.append("session data is not an object")
		return null
	var catalog := PortCatalog.get_default()
	var state := SessionState.new()

	var boat: Variant = data.get("boat")
	if not boat is Dictionary or not boat.get("area") is String:
		errors.append("missing boat area")
		return null
	state.boat_area = StringName(boat["area"])
	if state.boat_area not in BOAT_AREAS:
		errors.append("unknown boat area: %s" % state.boat_area)
		return null

	var player: Variant = data.get("player")
	if not player is Dictionary:
		errors.append("missing player data")
		return null
	var position: Variant = player.get("position")
	if position is Dictionary:
		var x: Variant = position.get("x")
		var y: Variant = position.get("y")
		if not (_is_finite_number(x) and _is_finite_number(y)):
			errors.append("invalid player position")
			return null
		state.player_position = Vector2(float(x), float(y))
		state.has_player_position = true
	elif player.get("spawn_point") is String:
		state.spawn_point = StringName(player["spawn_point"])
	else:
		errors.append("player has neither a position nor a spawn point")
		return null

	var clock: Variant = data.get("clock")
	if not clock is Dictionary or not _is_finite_number(clock.get("game_time")) \
			or not _is_finite_number(clock.get("time_scale")):
		errors.append("missing or invalid clock")
		return null
	state.game_time = float(clock.game_time)
	state.time_scale = int(clock.time_scale)
	# Optional (added in the I003b UI hotfix; older saves are simply not paused).
	var saved_paused: Variant = clock.get("paused", false)
	if not saved_paused is bool:
		errors.append("invalid pause state")
		return null
	state.paused = saved_paused
	if state.game_time < 0.0 or state.time_scale not in TIME_SCALES:
		errors.append("invalid game time or time acceleration")
		return null

	var wind: Variant = data.get("wind")
	if not wind is Dictionary or not _is_finite_number(wind.get("seed")):
		errors.append("missing or invalid wind settings")
		return null
	state.wind_seed = int(wind.seed)
	var weather: Variant = data.get("weather")
	if not weather is Dictionary or not _is_finite_number(weather.get("model_version")):
		errors.append("missing or invalid weather data")
		return null
	state.weather_model_version = int(weather.model_version)
	state.weather_exposure = WeatherExposure.from_dict(weather.get("exposure"), errors)
	if state.weather_exposure == null:
		return null
	state.companion = CompanionState.from_dict(data.get("companion"), errors)
	if state.companion == null:
		return null

	var vessel: Variant = data.get("vessel")
	if not vessel is Dictionary or not vessel.get("status") is String:
		errors.append("missing or invalid vessel data")
		return null
	state.vessel_status = StringName(vessel.status)
	var vessel_position: Variant = PlannedRoute._point_from(vessel.get("position"))
	if state.vessel_status not in STATUSES or vessel_position == null:
		errors.append("invalid vessel status or position")
		return null
	state.vessel_position = vessel_position
	# An unknown id is not an error here: GameSession falls back to the starter
	# boat and tells the player (so a save with a removed boat still loads).
	if not vessel.get("id") is String or String(vessel.id).is_empty():
		errors.append("missing vessel id")
		return null
	state.vessel_id = StringName(vessel.id)
	state.propulsion = PropulsionState.from_dict(vessel.get("propulsion"), errors)
	if state.propulsion == null:
		return null
	var trim: Variant = vessel.get("sail_trim")
	if trim is Dictionary and trim.get("auto") is bool and _is_finite_number(trim.get("value")):
		state.trim_auto = trim.auto
		state.trim_value = clampf(float(trim.value), -1.0, 1.0)
	var conditions: Variant = vessel.get("conditions")
	if not conditions is Dictionary or not _is_finite_number(vessel.get("damage_applied_until")):
		errors.append("missing or invalid vessel condition")
		return null
	for id: Variant in conditions:
		if not id is String or not _is_finite_number(conditions[id]):
			errors.append("invalid vessel condition")
			return null
		state.vessel_conditions[id] = clampf(float(conditions[id]), 0.0, VesselCondition.FULL)
	state.damage_applied_until = float(vessel.damage_applied_until)

	var economy: Variant = data.get("economy")
	if not economy is Dictionary or not _is_finite_number(economy.get("funds")) or int(economy.funds) < 0:
		errors.append("missing or invalid funds")
		return null
	state.funds = int(economy.funds)
	state.provisions = Provisions.from_dict(data.get("provisions"), errors)
	if state.provisions == null:
		return null
	var rescue: Variant = data.get("rescue")
	if not rescue is Dictionary or not _is_finite_number(rescue.get("count")) or not rescue.get("last", {}) is Dictionary:
		errors.append("missing or invalid rescue record")
		return null
	state.rescue_count = maxi(int(rescue.count), 0)
	state.last_rescue = (rescue.get("last", {}) as Dictionary).duplicate(true)
	state.captains_log = CaptainsLog.from_dict(data.get("log"), errors)
	if state.captains_log == null:
		return null
	state.progress = ObjectiveProgress.from_dict(data.get("progress"), errors)
	if state.progress == null:
		return null
	state.hat = HatState.from_dict(data.get("hat"), errors)
	if state.hat == null:
		return null
	state.fishing = FishingState.from_dict(data.get("fishing"), errors)
	if state.fishing == null:
		return null
	state.galley = GalleyState.from_dict(data.get("galley"), errors)
	if state.galley == null:
		return null
	state.anchor = AnchorState.from_dict(data.get("anchor"), errors)
	if state.anchor == null:
		return null
	var care: Variant = data.get("boat_care")
	if not care is Dictionary:
		errors.append("missing boat care data")
		return null
	for id: Variant in care:
		var record := BoatCareState.from_dict(care[id], errors)
		if record == null:
			return null
		state.boat_care[String(id)] = record
	# I020, optional: older saves have plain cabins and classic sails.
	state.home = HomeState.from_dict(data.get("home"))
	# I022, optional: the boats owned (older saves own every boat, as they
	# could move aboard any of them) and the difficulty (older saves: Standard).
	state.owned_vessels = owned_from(data.get("fleet"), state.vessel_id)
	state.difficulty = Difficulty.valid(data.get("difficulty"))
	state.pastimes = PastimesState.from_dict(data.get("pastimes"))

	var navigation: Variant = data.get("navigation")
	if not navigation is Dictionary:
		errors.append("missing navigation data")
		return null
	var location: Variant = navigation.get("location_id")
	if not location is String:
		errors.append("invalid location")
		return null
	state.location_id = StringName(location)
	var underway := state.vessel_status == STATUS_UNDERWAY
	if underway != state.location_id.is_empty():
		errors.append("location does not match the vessel status")
		return null
	if not underway and not catalog.has_port(state.location_id):
		errors.append("unknown location: %s" % [location])
		return null
	var route_data: Variant = navigation.get("planned_route")
	if route_data != null:
		state.planned_route = PlannedRoute.from_dict(route_data, catalog, errors)
		if state.planned_route == null:
			return null
	var voyage_data: Variant = navigation.get("voyage")
	if underway != (voyage_data != null):
		errors.append("voyage data does not match the vessel status")
		return null
	if underway:
		state.voyage = Voyage.from_dict(voyage_data, catalog, errors)
		if state.voyage == null:
			return null
		if state.anchor.active:
			# At anchor the boat lies where the anchor holds it (Iteration 13).
			state.vessel_position = state.anchor.position
		elif not GeoMath.same_position(state.voyage.get_position(), state.vessel_position, 0.001):  # wrap-aware (Date Line)
			errors.append("vessel position does not match the voyage progress")
			return null
		else:
			# Use the exact derived position so the simulation continues seamlessly.
			state.vessel_position = state.voyage.get_position()
	if state.anchor.active and not underway:
		errors.append("the boat is at anchor but not on a voyage")
		return null
	return state


static func _is_finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
