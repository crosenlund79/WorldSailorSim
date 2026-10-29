class_name Economy
extends RefCounted
## The running costs of a life afloat (I027, The Cost of the Wind): fuel and
## harbour dues, read from the one balance file data/economy/economy.json.
## Pure and static: prices for a harbour and a boat, a boat's tank and burn,
## and the nights between two times on a harbour's own clock. GameSession
## charges them (once, through its ledger); the menus only show them.

const DATA_PATH := "res://data/economy/economy.json"
const METRES_PER_FOOT := 0.3048

static var _data: Dictionary


static func _catalogue() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_data = parsed if parsed is Dictionary else {}
	return _data


static func _vessel(vessel_id: StringName) -> Dictionary:
	var vessels: Dictionary = _catalogue().get("vessels", {})
	return vessels.get(String(vessel_id), _catalogue().get("default_vessel", {"fuel_tank_l": 100, "fuel_burn_lph": 3.0}))


## Litres a boat's tank holds.
static func tank_l(vessel_id: StringName) -> float:
	return float(_vessel(vessel_id).get("fuel_tank_l", 100.0))


## Litres an hour its engine burns at cruising revs.
static func burn_lph(vessel_id: StringName) -> float:
	return float(_vessel(vessel_id).get("fuel_burn_lph", 3.0))


## Fuel price per litre in a harbour (euros, before the difficulty's costs).
static func fuel_price_per_litre(port_id: StringName) -> float:
	var fuel: Dictionary = _catalogue().get("fuel", {})
	var region := String(HarbourDressing.archetype_for(port_id))
	var tier := String(HarbourFacilities.for_port(port_id).get_tier())
	var price := float((fuel.get("price_per_litre_eur", {}) as Dictionary).get(region, 2.0))
	return price * float((fuel.get("tier_factor", {}) as Dictionary).get(tier, 1.0))


## Below this share of the tank the Captain is told.
static func low_fuel_share() -> float:
	return float((_catalogue().get("fuel", {}) as Dictionary).get("low_warning_share", 0.25))


## Harbour dues for one night (euros, before the difficulty's costs).
static func dues_per_night(port_id: StringName, length_ft: float) -> float:
	var dues: Dictionary = _catalogue().get("harbour_dues", {})
	var tier := String(HarbourFacilities.for_port(port_id).get_tier())
	var region := String(HarbourDressing.archetype_for(port_id))
	var per_metre := float((dues.get("per_metre_night_eur", {}) as Dictionary).get(tier, 2.4))
	return per_metre * length_ft * METRES_PER_FOOT * float((dues.get("region_factor", {}) as Dictionary).get(region, 1.0))


static func grace_hours() -> float:
	return float((_catalogue().get("harbour_dues", {}) as Dictionary).get("grace_hours", 6.0))


## Nights moored between `from` and `to` (game times): the harbour's local
## midnights in between; a stop shorter than grace_hours is none.
static func nights(port_id: StringName, from: float, to: float) -> int:
	if from <= 0.0 or to - from < grace_hours() * 3600.0:
		return 0
	var lon := BusinessHours.longitude_of(port_id)
	var day_from := floori((from + lon / 15.0 * 3600.0) / 86400.0)
	var day_to := floori((to + lon / 15.0 * 3600.0) / 86400.0)
	return maxi(day_to - day_from, 1)
