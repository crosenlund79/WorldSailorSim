class_name BusinessHours
extends RefCounted
## Opening hours of the quay's businesses (I026 stage 02, living harbours).
##
## Data-driven (data/harbours/business_hours.json): each business type has an
## opening and a closing hour and the weekdays it stays shut; the harbour's
## regional archetype (HarbourDressing.archetype_for: a Mediterranean quay
## opens a little later and stays open into the evening) and its service
## tier (HarbourFacilities: a small harbour keeps shorter hours, a major one
## longer) nudge them. The café opens early, the sail loft late, the boatyard
## keeps working hours and rests on Sundays.
##
## Everything is on the harbour's local solar time (Daylight.local_solar_hours,
## from its longitude) and read from the one authoritative clock
## (GameSession game time), so a shop is open or shut exactly when the light
## says it is morning or evening there. Nothing is saved: the hours follow
## from the harbour and the clock. The harbour office's after-hours hatch is
## always staffed (essential things stay possible at any hour).

const DATA_PATH := "res://data/harbours/business_hours.json"
const HOUR := 3600.0
const DAY := 86400.0

static var _data: Dictionary


static func _catalogue() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_data = parsed if parsed is Dictionary else {"businesses": {}, "regions": {}, "tiers": {}}
	return _data


## The business types with hours (ids, as in QuayLayout).
static func get_types() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: String in (_catalogue().get("businesses", {}) as Dictionary):
		out.append(StringName(key))
	return out


static func has_hours(business: StringName) -> bool:
	return (_catalogue().get("businesses", {}) as Dictionary).has(String(business))


## The harbour's longitude (its catalogue position; 0 when unknown).
static func longitude_of(port_id: StringName) -> float:
	var port := PortCatalog.get_default().get_port(port_id) if not port_id.is_empty() else null
	return port.longitude if port else 0.0


## Opening and closing hour of `business` at `port_id` (local solar hours,
## x = open, y = close), with the region's and the tier's nudges. A business
## without hours (the noticeboard, the lane into town) is always open: (0, 24).
static func hours(business: StringName, port_id: StringName) -> Vector2:
	var entry: Dictionary = (_catalogue().get("businesses", {}) as Dictionary).get(String(business), {})
	if entry.is_empty():
		return Vector2(0.0, 24.0)
	var open := float(entry.get("open", 8.0))
	var close := float(entry.get("close", 17.0))
	var region: Dictionary = (_catalogue().get("regions", {}) as Dictionary).get(String(HarbourDressing.archetype_for(port_id)), {})
	var tier: Dictionary = (_catalogue().get("tiers", {}) as Dictionary).get(String(HarbourFacilities.for_port(port_id).get_tier()), {})
	open += float(region.get("open", 0.0)) + float(tier.get("open", 0.0))
	close += float(region.get("close", 0.0)) + float(tier.get("close", 0.0))
	open = clampf(open, 0.0, 23.0)
	close = clampf(close, open + 1.0, 24.0)
	return Vector2(open, close)


## Local weekdays the business stays shut (0 = Sunday).
static func closed_days(business: StringName) -> Array:
	var entry: Dictionary = (_catalogue().get("businesses", {}) as Dictionary).get(String(business), {})
	return entry.get("closed", [])


## The harbour's local solar time of day (hours, 0..24).
static func local_hours(port_id: StringName, time: float) -> float:
	return Daylight.local_solar_hours(longitude_of(port_id), time)


## The harbour's local weekday (0 = Sunday), on its solar time.
static func local_weekday(port_id: StringName, time: float) -> int:
	var local := time + longitude_of(port_id) / 15.0 * HOUR
	# 1 January 1970 was a Thursday (4).
	return posmod(floori(local / DAY) + 4, 7)


static func is_open(business: StringName, port_id: StringName, time: float) -> bool:
	if not has_hours(business):
		return true
	if local_weekday(port_id, time) in closed_days(business):
		return false
	var span := hours(business, port_id)
	var h := local_hours(port_id, time)
	return h >= span.x and h < span.y


## The game time the business next opens (`time` itself while it is open).
static func next_opening(business: StringName, port_id: StringName, time: float) -> float:
	if is_open(business, port_id, time):
		return time
	var span := hours(business, port_id)
	var midnight := time - local_hours(port_id, time) * HOUR  # local midnight today
	for d in 9:
		var at := midnight + d * DAY + span.x * HOUR
		if at > time and not local_weekday(port_id, at) in closed_days(business):
			return at
	return time


## The game time it closes (when open now), else -1.
static func closing_time(business: StringName, port_id: StringName, time: float) -> float:
	if not is_open(business, port_id, time) or not has_hours(business):
		return -1.0
	var midnight := time - local_hours(port_id, time) * HOUR
	return midnight + hours(business, port_id).y * HOUR


## "07:30".
static func format_hour(h: float) -> String:
	var minutes := roundi(h * 60.0)
	return "%02d:%02d" % [posmod(minutes / 60, 24) if minutes < 1440 else 24, minutes % 60]


## "08:00–17:00", with the closed day ("08:00–17:00, closed Sundays").
static func describe(business: StringName, port_id: StringName) -> String:
	if not has_hours(business):
		return Loc.t("always open")
	var span := hours(business, port_id)
	var text := "%s–%s" % [format_hour(span.x), format_hour(span.y)]
	var days := closed_days(business)
	if days.size() == 1:
		text = Loc.t("%s, closed on %s") % [text, Loc.weekday(int(days[0]))]
	return text


## The door's short state for the prompt and the hours plate:
## "open until 17:00" or "closed · opens 09:00 (in 3 h 10 min)" or
## "closed · opens Monday 09:00".
static func status_text(business: StringName, port_id: StringName, time: float) -> String:
	if not has_hours(business):
		return Loc.t("open")
	if is_open(business, port_id, time):
		return Loc.t("open until %s") % format_hour(hours(business, port_id).y)
	var at := next_opening(business, port_id, time)
	var wait := at - time
	var clock := format_hour(local_hours(port_id, at))
	if wait < 20.0 * HOUR:
		return Loc.t("closed · opens %s (in %s)") % [clock, Simulation.format_duration(wait)]
	return Loc.t("closed · opens %s %s") % [Loc.weekday(local_weekday(port_id, at)), clock]
