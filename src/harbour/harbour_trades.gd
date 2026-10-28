class_name HarbourTrades
extends RefCounted
## The harbour trades (I020, A Boat of Your Own): the chandlery, the
## sailmaker and the fishmonger, and the small things for a cabin.
##
## The catalogue is data (data/harbours/trades/trades.json). Which harbour
## has which trade follows its facilities (HarbourFacilities, the existing
## data per harbour), so no harbour needs a list of its own and an
## international harbour works like a Danish one:
##   - the fishmonger wherever there is a grocery store (every harbour unless
##     its facilities say otherwise): selling the catch is never far away;
##   - the chandlery and the sailmaker wherever there is a boatyard.
## Everything sold here is optional: the boat sails, fishes and is cared for
## exactly as before without it.

const CATALOGUE_PATH := "res://data/harbours/trades/trades.json"
const DECOR_FLOOR := &"floor"
const DECOR_SHELF := &"shelf"
const DECOR_WALL := &"wall"
const CLASSIC_CLOTH := "classic"

static var _data: Dictionary


static func _catalogue() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOGUE_PATH))
		_data = parsed if parsed is Dictionary else {"decor": [], "sail_cloths": [], "chandlery": {}, "fishmongers": []}
	return _data


## Whether `facilities` (a harbour's) include `trade` (HarbourFacilities
## CHANDLERY, SAILMAKER or FISHMONGER).
static func offered(facilities: HarbourFacilities, trade: StringName) -> bool:
	if facilities == null:
		return false
	match trade:
		HarbourFacilities.FISHMONGER:
			return facilities.grocery
		HarbourFacilities.CHANDLERY, HarbourFacilities.SAILMAKER:
			return facilities.boatyard
	return false


# --- Cabin things -------------------------------------------------------------------------

static func get_decor() -> Array:
	return _catalogue().get("decor", [])


static func get_decor_item(id: String) -> Dictionary:
	for item: Dictionary in get_decor():
		if String(item.id) == id:
			return item
	return {}


# --- Sailcloth --------------------------------------------------------------------------

static func get_sail_cloths() -> Array:
	return _catalogue().get("sail_cloths", [])


static func get_sail_cloth(id: String) -> Dictionary:
	for cloth: Dictionary in get_sail_cloths():
		if String(cloth.id) == id:
			return cloth
	return {}


## Cutting a suit of sails in `id` for a boat of `length_ft`.
static func sail_cloth_price(id: String, length_ft: float) -> int:
	return roundi(float(get_sail_cloth(id).get("price_per_ft", 0)) * length_ft / 10.0) * 10


## [sail, shade] colours of a cloth (the classic cream when unknown).
static func sail_colours(id: String) -> Array[Color]:
	var cloth := get_sail_cloth(id)
	if cloth.is_empty():
		cloth = get_sail_cloth(CLASSIC_CLOTH)
	return [Color(String(cloth.get("sail", "#E3E2DA"))), Color(String(cloth.get("shade", "#BDBEB7")))]


# --- The chandlery ----------------------------------------------------------------------

## The boat-care upgrades the chandlery fits (the rest is yard work).
static func get_chandlery_upgrades() -> Array:
	return (_catalogue().get("chandlery", {}) as Dictionary).get("upgrades", [])


static func is_chandlery_upgrade(id: String) -> bool:
	return id in get_chandlery_upgrades()


static func get_magic_anchor_price() -> int:
	return int((_catalogue().get("chandlery", {}) as Dictionary).get("magic_anchor_price", 450))


# --- The fishmonger ---------------------------------------------------------------------

## The fishmonger at `port_id` (a name; the same every visit).
static func fishmonger_name(port_id: StringName) -> String:
	var names: Array = _catalogue().get("fishmongers", [])
	return String(names[absi(hash(String(port_id))) % names.size()]) if not names.is_empty() else ""
