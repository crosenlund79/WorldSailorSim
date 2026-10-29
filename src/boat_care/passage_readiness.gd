class_name PassageReadiness
extends RefCounted
## Passage Readiness (Iteration 14): a friendly look at a planned passage
## before setting out. Advisory only: it never stops a departure.
##
## It weighs the boat's condition (the hull and the care areas), food and
## water against the expected passage time, the weather foreseen on the
## route (the same forecast as the chart's weather warnings), the passage's
## length and the boat itself (a small boat is happier waiting out rough
## weather). Each finding has a level: OK (nothing to do), NOTE (worth
## knowing) or CONSIDER (worth a second thought).
##
## Iteration 16, ocean passages: the forecast only reaches FORECAST_HOURS,
## and the readiness says so instead of promising fair weather for weeks; the
## stores are weighed against what the boat can stow for a long passage.

const OK := 0
const NOTE := 1
const CONSIDER := 2
const SUMMARIES := {OK: "Ready to sail.", NOTE: "Ready to sail, with a few things to note.",
	CONSIDER: "Worth a second thought before setting out."}
## Food and water to spare beyond the passage itself (days).
const STORES_MARGIN_DAYS := 1.0
const STORES_COMFORT_DAYS := 2.0
## A passage longer than this runs through a night (hours).
const OVERNIGHT_HOURS := 14.0
const LONG_PASSAGE_HOURS := 48.0
## An ocean passage: a week or more at sea (hours).
const OCEAN_PASSAGE_HOURS := 168.0
## Boats this short (ft) count as small for rough weather.
const SMALL_BOAT_FT := 28.0
## I027: below this share of the tank a long passage gets a fuel note.
const LOW_FUEL_SHARE := 0.5
## How far ahead the forecast is consulted (hours, at most the passage).
const FORECAST_HOURS := 24.0


## Assesses `path` (a planned course from here) for the active boat.
## Returns {"level", "summary", "items": [{"topic", "level", "text"}],
## "hours", "nm"}.
static func assess(path: PackedVector2Array) -> Dictionary:
	var items: Array[Dictionary] = []
	var nm := GeoMath.path_length_nm(path) if path.size() >= 2 else 0.0
	var hours := Simulation.estimate_route_seconds(path) / 3600.0 if path.size() >= 2 else 0.0
	var vessel := GameSession.get_vessel_definition()
	_boat(items, hours)
	_stores(items, hours)
	_fuel(items, hours)
	var worst_hazard := _weather(items, path, hours)
	_length(items, hours)
	var length_ft := GameSession.get_base_vessel_profile().length_ft
	if length_ft <= SMALL_BOAT_FT and (worst_hazard >= WeatherModel.HAZARD_CAUTION or hours > LONG_PASSAGE_HOURS):
		items.append({"topic": "boat_size", "level": NOTE, "text": Loc.t("The %s is a small boat: she is happiest making long or rough passages in settled weather.") % vessel.display_name})
	var level := OK
	for item in items:
		level = maxi(level, int(item.level))
	return {"level": level, "summary": SUMMARIES[level], "items": items, "hours": hours, "nm": nm}


## The findings worth showing, in a few short lines (NOTE and CONSIDER first;
## the reassuring ones when there is nothing else).
static func describe(result: Dictionary, max_lines := 4) -> String:
	var lines := PackedStringArray([String(result.summary)])
	var shown := 0
	for level in [CONSIDER, NOTE]:
		for item: Dictionary in result.items:
			if int(item.level) == level and shown < max_lines:
				lines.append("• " + String(item.text))
				shown += 1
	if shown == 0:
		for item: Dictionary in result.items:
			if shown < 2:
				lines.append("• " + String(item.text))
				shown += 1
	return "\n".join(lines)


static func _boat(items: Array[Dictionary], hours: float) -> void:
	var condition := GameSession.get_condition()
	var name := GameSession.get_vessel_definition().display_name
	match VesselCondition.band_of(condition):
		VesselCondition.BAND_SOUND:
			items.append({"topic": "hull", "level": OK, "text": Loc.t("The %s is sound (%d %%).") % [name, roundi(condition)]})
		VesselCondition.BAND_WORN:
			items.append({"topic": "hull", "level": CONSIDER if hours > OVERNIGHT_HOURS else NOTE,
				"text": Loc.t("The hull is worn (%d %%). Fine for a short hop; a boatyard repair would be wise before a long passage.") % roundi(condition)})
		_:
			items.append({"topic": "hull", "level": CONSIDER,
				"text": Loc.t("The hull is damaged (%d %%). Rough weather would be hard on her; a repair first would be wise.") % roundi(condition)})
	var care := GameSession.get_boat_care()
	var now := GameSession.get_game_time()
	for area in [BoatCare.AREA_HULL, BoatCare.AREA_RIG, BoatCare.AREA_ENGINE]:
		var level := BoatCare.area_level(area, care, condition, now)
		if area == BoatCare.AREA_HULL:
			# The damage is covered above; here only the bottom.
			level = BoatCare._level(BoatCare.fouling(care, now), BoatCare.FOULING_COSMETIC, BoatCare.FOULING_RECOMMENDED, BoatCare.FOULING_NEEDED)
		if level == BoatCare.LEVEL_RECOMMENDED or level == BoatCare.LEVEL_NEEDED:
			var text: String = {BoatCare.AREA_HULL: Loc.t("Weed on the bottom is slowing her a little; a haul-out would clean it."),
				BoatCare.AREA_RIG: Loc.t("The rigging and sails are due a service; they lose a little speed and take weather harder."),
				BoatCare.AREA_ENGINE: Loc.t("The engine is due a service; it is a little slower under power.")}[area]
			items.append({"topic": String(area), "level": NOTE, "text": text})


static func _stores(items: Array[Dictionary], hours: float) -> void:
	var provisions := GameSession.get_provisions()
	var days := minf(provisions.food_days, provisions.water_days)
	var needed := hours / 24.0
	if days < needed + STORES_MARGIN_DAYS:
		items.append({"topic": "stores", "level": CONSIDER, "text": Loc.t("Food or water may run short: %s aboard for a passage of about %s.") % [
			Provisions.format_days(days), Simulation.format_duration(hours * 3600.0)]})
		var capacity := GameSession.get_passage_store_days()
		if capacity >= needed + STORES_MARGIN_DAYS and days < capacity:
			items.append({"topic": "stores_capacity", "level": NOTE,
				"text": Loc.t("At the grocery store you can stock up for a long passage: the %s stows up to %d days.") % [
					GameSession.get_vessel_definition().display_name, roundi(capacity)]})
		elif capacity < needed + STORES_MARGIN_DAYS:
			items.append({"topic": "stores_capacity", "level": CONSIDER,
				"text": Loc.t("This passage is longer than the %s can stow food and water for (%d days). A stop on the way would break it up; a bigger boat stows more.") % [
					GameSession.get_vessel_definition().display_name, roundi(capacity)]})
	elif days < needed + STORES_COMFORT_DAYS:
		items.append({"topic": "stores", "level": NOTE, "text": Loc.t("Enough food and water for the passage, with little to spare (%s).") % Provisions.format_days(days)})
	else:
		items.append({"topic": "stores", "level": OK, "text": Loc.t("Food and water for %s.") % Provisions.format_days(days)})


## I027: a long passage on a low tank. The estimate already counts the fuel
## aboard; a full tank carries the boat through the calms.
static func _fuel(items: Array[Dictionary], hours: float) -> void:
	var tank := GameSession.get_fuel_tank_l()
	if hours <= LONG_PASSAGE_HOURS or tank <= 0.0 or GameSession.test_fuel_unlimited:
		return
	var share := GameSession.get_fuel_l() / tank
	if share < LOW_FUEL_SHARE:
		items.append({"topic": "fuel", "level": NOTE, "text": Loc.t("The fuel tank is %d %% full. A full tank carries her through calms and can shorten the passage.") % roundi(share * 100.0)})


## Adds the weather finding; returns the worst hazard level foreseen.
static func _weather(items: Array[Dictionary], path: PackedVector2Array, hours: float) -> int:
	var hazards := Simulation.route_hazards(path, 0.0, clampf(hours, 1.0, FORECAST_HOURS))
	var beyond := hours > FORECAST_HOURS
	var worst := WeatherModel.HAZARD_NORMAL
	var strongest := 0.0
	var label := ""
	var when := 0.0
	for hazard in hazards:
		if int(hazard.hazard) > worst:
			worst = int(hazard.hazard)
			label = String(hazard.label)
			when = float(hazard.hours)
		strongest = maxf(strongest, float(hazard.speed_kn))
	if worst >= WeatherModel.HAZARD_DANGEROUS:
		items.append({"topic": "weather", "level": CONSIDER, "text": Loc.t("%s expected on the route %s (wind up to %d kn). Waiting in harbour may be kinder.") % [
			label, Simulation.describe_when(when), roundi(strongest)]})
	elif worst >= WeatherModel.HAZARD_CAUTION:
		items.append({"topic": "weather", "level": NOTE, "text": Loc.t("A fresh to strong breeze on the way (up to %d kn) %s.") % [
			roundi(strongest), Simulation.describe_when(when)]})
	elif beyond:
		items.append({"topic": "weather", "level": OK, "text": Loc.t("No rough weather foreseen in the next %d hours.") % roundi(FORECAST_HOURS)})
	else:
		items.append({"topic": "weather", "level": OK, "text": Loc.t("No rough weather foreseen on the route.")})
	if beyond:
		items.append({"topic": "forecast", "level": NOTE,
			"text": Loc.t("The forecast reaches %d hours ahead; the weather further along the passage is not yet known.") % roundi(FORECAST_HOURS)})
	return worst


static func _length(items: Array[Dictionary], hours: float) -> void:
	if hours > OCEAN_PASSAGE_HOURS:
		items.append({"topic": "length", "level": NOTE, "text": Loc.t("An ocean passage of about %s. Long Passage time on deck lets the days go by.") % Simulation.format_duration(hours * 3600.0)})
	elif hours > LONG_PASSAGE_HOURS:
		items.append({"topic": "length", "level": NOTE, "text": Loc.t("A passage of several days (about %s): the weather can change on the way.") % Simulation.format_duration(hours * 3600.0)})
	elif hours > OVERNIGHT_HOURS:
		items.append({"topic": "length", "level": NOTE, "text": Loc.t("An overnight passage (about %s). A rest before setting out helps.") % Simulation.format_duration(hours * 3600.0)})
