class_name Accommodation
extends RefCounted
## What each boat offers people aboard (Between Horizons, I027 Tier 3): its
## safe capacity, sleeping places, cabins, heads, comfort and the passages it
## is fitted for, read from data/vessels/accommodation.json. The data follows
## the drawn cabin (every place names the node that draws it, and
## test_accommodation checks it), so a boat never offers what it does not show.
##
## The booking queries for the passenger trade (I028) live here, in one
## place: safe_guest_count, overnight_guest_count, private_guest_cabins,
## skipper_has_privacy, comfort_tier, passage_suitability. Pure and static;
## nothing is saved (a boat's accommodation is part of the boat).

const DATA_PATH := "res://data/vessels/accommodation.json"

const SIZE_SMALL := &"small"
const SIZE_MEDIUM := &"medium"
const SIZE_LARGE := &"large"
const COMFORT_SIMPLE := &"simple"
const COMFORT_COMFORTABLE := &"comfortable"
const COMFORT_SPACIOUS := &"spacious"
const COMFORT_ORDER: Array[StringName] = [COMFORT_SIMPLE, COMFORT_COMFORTABLE, COMFORT_SPACIOUS]
const PASSAGE_COASTAL := &"coastal"
const PASSAGE_OFFSHORE := &"offshore"
const PASSAGE_OCEAN := &"ocean"
const PASSAGE_ORDER: Array[StringName] = [PASSAGE_COASTAL, PASSAGE_OFFSHORE, PASSAGE_OCEAN]
const QUALITY_BASIC := &"basic"
const QUALITY_GOOD := &"good"
const QUALITY_FINE := &"fine"
const SPACE_SHARED := "shared"
const FOR_SKIPPER := "skipper"

## A boat missing from the file: the skipper alone, coastal.
const FALLBACK := {"size_class": "small", "comfort": "simple", "passage": "coastal", "safe_persons": 1,
	"sleeping": [{"id": "berth", "label": "Berth", "sleeps": 1, "quality": "basic", "space": "shared", "for": "skipper"}],
	"cabins": [], "heads": [], "showers": 0, "amenities": []}

static var _data: Dictionary


static func _catalogue() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_data = parsed if parsed is Dictionary else {}
	return _data


## The boat's whole entry (a copy is not made: read only).
static func of(vessel_id: StringName) -> Dictionary:
	return (_catalogue().get("vessels", {}) as Dictionary).get(String(vessel_id), FALLBACK)


static func has_data(vessel_id: StringName) -> bool:
	return (_catalogue().get("vessels", {}) as Dictionary).has(String(vessel_id))


## The most people the boat safely carries under way, the skipper included.
static func safe_persons(vessel_id: StringName) -> int:
	return int(of(vessel_id).get("safe_persons", 1))


## Guests by day: the safe capacity less the skipper.
static func safe_guest_count(vessel_id: StringName) -> int:
	return maxi(safe_persons(vessel_id) - 1, 0)


## Guests who can sleep aboard: the places not kept for the skipper, never
## more than the boat safely carries.
static func overnight_guest_count(vessel_id: StringName) -> int:
	var places := 0
	for place: Dictionary in of(vessel_id).get("sleeping", []):
		if String(place.get("for", "")) != FOR_SKIPPER:
			places += int(place.get("sleeps", 1))
	return mini(places, safe_guest_count(vessel_id))


## Private cabins (with a door) for guests.
static func private_guest_cabins(vessel_id: StringName) -> int:
	var count := 0
	for cabin: Dictionary in of(vessel_id).get("cabins", []):
		if bool(cabin.get("private", false)) and String(cabin.get("for", "")) != FOR_SKIPPER:
			count += 1
	return count


## True when the skipper sleeps in a private cabin of their own.
static func skipper_has_privacy(vessel_id: StringName) -> bool:
	for place: Dictionary in of(vessel_id).get("sleeping", []):
		if String(place.get("for", "")) == FOR_SKIPPER:
			var cabin := _cabin(vessel_id, String(place.get("space", SPACE_SHARED)))
			return bool(cabin.get("private", false))
	return false


## simple, comfortable or spacious: how it feels to live aboard.
static func comfort_tier(vessel_id: StringName) -> StringName:
	return StringName(of(vessel_id).get("comfort", COMFORT_SIMPLE))


## coastal, offshore or ocean: the furthest kind of passage it is fitted for.
static func passage_suitability(vessel_id: StringName) -> StringName:
	return StringName(of(vessel_id).get("passage", PASSAGE_COASTAL))


## True when the boat is fitted for `kind` of passage (coastal < offshore < ocean).
static func suits_passage(vessel_id: StringName, kind: StringName) -> bool:
	return PASSAGE_ORDER.find(passage_suitability(vessel_id)) >= PASSAGE_ORDER.find(kind)


## small, medium or large (length and price; the running costs follow).
static func size_class(vessel_id: StringName) -> StringName:
	return StringName(of(vessel_id).get("size_class", SIZE_SMALL))


## Enclosed heads (toilet compartments) aboard.
static func heads_count(vessel_id: StringName) -> int:
	return (of(vessel_id).get("heads", []) as Array).size()


## Everyone the boat can sleep, the skipper included.
static func sleeping_places(vessel_id: StringName) -> int:
	var places := 0
	for place: Dictionary in of(vessel_id).get("sleeping", []):
		places += int(place.get("sleeps", 1))
	return places


static func _cabin(vessel_id: StringName, cabin_id: String) -> Dictionary:
	for cabin: Dictionary in of(vessel_id).get("cabins", []):
		if String(cabin.get("id", "")) == cabin_id:
			return cabin
	return {}


## The boatyard's lines about life aboard: [label, value] rows.
static func describe_rows(vessel_id: StringName) -> Array:
	var data := of(vessel_id)
	var berths := PackedStringArray()
	var counted := {}
	for place: Dictionary in data.get("sleeping", []):
		var label := String(place.get("label", ""))
		counted[label] = int(counted.get(label, 0)) + 1
	for label: String in counted:
		berths.append(Loc.t(label) if int(counted[label]) == 1 else "%d × %s" % [int(counted[label]), Loc.t(label)])
	var guests := Loc.t("%d by day, %d overnight") % [safe_guest_count(vessel_id), overnight_guest_count(vessel_id)]
	var cabins := private_guest_cabins(vessel_id)
	guests += "; " + (Loc.n("%d private guest cabin", "%d private guest cabins", cabins) % cabins if cabins > 0 else Loc.t("no private cabin"))
	var life := PackedStringArray([comfort_name(comfort_tier(vessel_id))])
	if skipper_has_privacy(vessel_id):
		life.append(Loc.t("the skipper's own cabin"))
	var heads := heads_count(vessel_id)
	life.append(Loc.n("%d heads", "%d heads", heads) % heads if heads > 0 else Loc.t("no enclosed heads"))
	return [[Loc.t("Sleeps"), "%d: %s" % [sleeping_places(vessel_id), ", ".join(berths)]],
		[Loc.t("Guests"), guests],
		[Loc.t("Aboard"), ", ".join(life)],
		[Loc.t("Suited to"), passage_name(passage_suitability(vessel_id))]]


static func comfort_name(tier: StringName) -> String:
	match tier:
		COMFORT_SPACIOUS:
			return Loc.t("Spacious")
		COMFORT_COMFORTABLE:
			return Loc.t("Comfortable")
	return Loc.t("Simple and snug")


static func passage_name(kind: StringName) -> String:
	match kind:
		PASSAGE_OCEAN:
			return Loc.t("Ocean passages")
		PASSAGE_OFFSHORE:
			return Loc.t("Offshore passages; oceans by way of island harbours")
	return Loc.t("Coastal hops")
