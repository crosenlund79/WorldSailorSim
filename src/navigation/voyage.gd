class_name Voyage
extends RefCounted
## An active voyage: the validated route being sailed and how far along it the
## vessel is. The vessel's position is always derived from `route.path` and
## `progress_nm`, so the chart, HUD, simulation and saves agree by construction.

## The course being sailed. After a change of course at sea its origin is the
## position where the change was made (origin_port_id is then empty).
var route: PlannedRoute
## Distance sailed along route.path, in nautical miles.
var progress_nm := 0.0
## Increases every time the course is replaced; weather warnings are
## de-duplicated per revision.
var revision := 1
## Weather condition ids already announced for this revision.
var warned_conditions: Array[StringName] = []
## Game time (seconds) when the vessel left the departure port.
var departed_at := 0.0
## Where the voyage began (kept through changes of course, which replace
## `route`): the port id, and its position.
var departure_port_id: StringName
var departure_position := Vector2.ZERO
## Distance actually sailed on this voyage, nm, across every change of course
## (progress_nm restarts with each new course). Advanced by the simulation.
var sailed_nm := 0.0
## The worst weather hazard (WeatherModel.HAZARD_*) the boat was in, and the
## condition (percent) the weather took from it on this voyage.
var worst_hazard := 0
var damage_percent := 0.0
## False for a voyage loaded from a save made before the Captain's Log
## (Iteration 006): its weather and damage before then are unknown.
var fully_recorded := true
## Anchorage waypoints (Iteration 18): `holding_at` is the route waypoint the
## boat has arrived at and waits at (stopped, not yet anchored; -1 when not
## waiting); `anchorages_done` the ones already reached (anchored at, or
## sailed on from), so none stops the boat twice. Optional in a save.
var holding_at := -1
var anchorages_done: Array[int] = []
## Standing by for a vessel that asked for help (I019, VHF): until this game
## time the boat stays where it is (the voyage pauses; the clock, weather and
## stores go on). 0 when not standing by. Optional in a save.
var standby_until := 0.0
## Sailing the leg (I027, CourseMaker): how far the boat is off the leg's line
## (nm, + to the right of it, - to the left), the side it is tacking or
## gybing on (+1 / -1; 0 = sailing the line), its heading relative to the
## leg (degrees, signed), when it last changed side, how many tacks and
## gybes this voyage, the tack time still to lose, until when a tack made
## by hand is kept, and the leg the course was set for. Optional in a save.
var cross_track_nm := 0.0
var tack_side := 0
var heading_offset_deg := 0.0
var tack_since := 0.0
var tack_count := 0
var tack_loss_left_s := 0.0
var manual_tack_until := 0.0
var course_leg := -1

const _COURSE_FIELDS := ["cross_track_nm", "tack_side", "heading_offset_deg", "tack_since", "tack_count",
	"tack_loss_left_s", "manual_tack_until", "course_leg"]

var _cumulative := PackedFloat64Array()


static func create(planned: PlannedRoute, start_time: float) -> Voyage:
	var voyage := Voyage.new()
	voyage.route = planned.duplicate_route()
	voyage.departed_at = start_time
	voyage.departure_port_id = planned.origin_port_id
	voyage.departure_position = planned.origin_position
	return voyage


func duplicate_voyage() -> Voyage:
	var copy := Voyage.new()
	copy.route = route.duplicate_route()
	copy.progress_nm = progress_nm
	copy.revision = revision
	copy.warned_conditions = warned_conditions.duplicate()
	copy.departed_at = departed_at
	copy.departure_port_id = departure_port_id
	copy.departure_position = departure_position
	copy.sailed_nm = sailed_nm
	copy.worst_hazard = worst_hazard
	copy.damage_percent = damage_percent
	copy.fully_recorded = fully_recorded
	copy.holding_at = holding_at
	copy.anchorages_done = anchorages_done.duplicate()
	copy.standby_until = standby_until
	for key: String in _COURSE_FIELDS:
		copy.set(key, get(key))
	return copy


## The route distance (nm) of waypoint `index`.
func waypoint_distance(index: int) -> float:
	return get_cumulative()[route.waypoint_path_indices[index]]


## The anchorage waypoint lying exactly at `distance_nm` that has not been
## reached yet, or -1.
func anchorage_at(distance_nm: float) -> int:
	for i in route.waypoints.size():
		if route.is_anchorage(i) and not i in anchorages_done and absf(waypoint_distance(i) - distance_nm) < 1e-6:
			return i
	return -1


## The next anchorage ahead: {"index", "nm", "geo"} or {}.
func next_anchorage() -> Dictionary:
	for i in route.waypoints.size():
		if route.is_anchorage(i) and not i in anchorages_done and waypoint_distance(i) >= progress_nm - 1e-6:
			return {"index": i, "nm": waypoint_distance(i) - progress_nm, "geo": route.waypoints[i]}
	return {}


## Anchorage flags for get_remaining_waypoints() (not yet reached ones only).
func get_remaining_anchorages() -> Array[bool]:
	var result: Array[bool] = []
	var cumulative := get_cumulative()
	for i in route.waypoints.size():
		if cumulative[route.waypoint_path_indices[i]] > progress_nm + 1e-6:
			result.append(route.is_anchorage(i) and not i in anchorages_done)
	return result


func get_cumulative() -> PackedFloat64Array:
	if _cumulative.size() != route.path.size():
		_cumulative = GeoMath.cumulative_distances(route.path)
	return _cumulative


func get_total_nm() -> float:
	var cumulative := get_cumulative()
	return cumulative[cumulative.size() - 1] if not cumulative.is_empty() else 0.0


func get_remaining_nm() -> float:
	return maxf(get_total_nm() - progress_nm, 0.0)


## Where the boat is: on the leg's line at its progress, plus its offset to
## the side while tacking (I027). The one position the chart, HUD, traffic
## and saves use.
func get_position() -> Vector2:
	var on_line := position_at(progress_nm)
	if absf(cross_track_nm) < 1e-9:
		return on_line
	return GeoMath.normalize(GeoMath.offset_nm(on_line, leg_bearing_at(progress_nm) + 90.0, cross_track_nm))


## A new course from where the boat is (a change of course, a re-planned
## route): it starts on its line, not tacking; the tack count is kept.
func reset_course() -> void:
	cross_track_nm = 0.0
	tack_side = 0
	heading_offset_deg = 0.0
	tack_loss_left_s = 0.0
	manual_tack_until = 0.0
	course_leg = -1


## The compass bearing of the leg at `distance_nm` along the course.
func leg_bearing_at(distance_nm: float) -> float:
	var i := leg_index_at(distance_nm)
	return GeoMath.rhumb_bearing(route.path[i - 1], route.path[i])


## The index (1..) of the path segment at `distance_nm`.
func leg_index_at(distance_nm: float) -> int:
	return GeoMath.segment_index_at(get_cumulative(), distance_nm)


## The distance (nm) still ahead on the current leg.
func remaining_leg_nm() -> float:
	var cumulative := get_cumulative()
	return maxf(cumulative[mini(leg_index_at(progress_nm), cumulative.size() - 1)] - progress_nm, 0.0)


## Within ±180° of longitude, also on a segment across the Date Line.
func position_at(distance_nm: float) -> Vector2:
	return GeoMath.normalize(GeoMath.point_along(route.path, get_cumulative(), distance_nm))


## The part of the course still ahead, starting at the vessel's position.
func get_remaining_path() -> PackedVector2Array:
	# From the line (a cut of the route), not the boat's offset while tacking.
	var result := PackedVector2Array([position_at(progress_nm)])
	var cumulative := get_cumulative()
	for i in route.path.size():
		if cumulative[i] > progress_nm + 1e-6:
			result.append(route.path[i])
	return result


## Player waypoints that are still ahead of the vessel.
func get_remaining_waypoints() -> Array[Vector2]:
	var result: Array[Vector2] = []
	var cumulative := get_cumulative()
	for i in route.waypoints.size():
		if cumulative[route.waypoint_path_indices[i]] > progress_nm + 1e-6:
			result.append(route.waypoints[i])
	return result


func is_complete() -> bool:
	return progress_nm >= get_total_nm() - 1e-9


func to_dict() -> Dictionary:
	return {
		"route": route.to_dict(),
		"progress_nm": progress_nm,
		"revision": revision,
		"warned_conditions": warned_conditions.map(func(id: StringName) -> String: return String(id)),
		"departed_at": departed_at,
		"departure_port_id": String(departure_port_id),
		"departure_position": {"lon": departure_position.x, "lat": departure_position.y},
		"sailed_nm": sailed_nm,
		"worst_hazard": worst_hazard,
		"damage_percent": damage_percent,
		"fully_recorded": fully_recorded,
		"holding_at": holding_at,
		"anchorages_done": anchorages_done.duplicate(),
		"standby_until": standby_until,
		"course": {"cross_track_nm": cross_track_nm, "tack_side": tack_side, "heading_offset_deg": heading_offset_deg,
			"tack_since": tack_since, "tack_count": tack_count, "tack_loss_left_s": tack_loss_left_s,
			"manual_tack_until": manual_tack_until, "course_leg": course_leg},
	}


static func from_dict(data: Variant, catalog: PortCatalog, errors: Array[String]) -> Voyage:
	if not data is Dictionary:
		errors.append("voyage is not an object")
		return null
	var voyage := Voyage.new()
	voyage.route = PlannedRoute.from_dict(data.get("route"), catalog, errors)
	if voyage.route == null:
		return null
	if not voyage.route.has_path():
		errors.append("voyage has no course")
		return null
	var progress: Variant = data.get("progress_nm")
	var revision: Variant = data.get("revision", 1)
	var departed: Variant = data.get("departed_at", 0.0)
	if not _is_number(progress) or float(progress) < 0.0 or float(progress) > voyage.get_total_nm() + 1e-6:
		errors.append("voyage progress is invalid")
		return null
	if not _is_number(revision) or int(revision) < 1 or not _is_number(departed):
		errors.append("voyage revision or departure time is invalid")
		return null
	voyage.progress_nm = float(progress)
	voyage.revision = int(revision)
	voyage.departed_at = float(departed)
	var warned: Variant = data.get("warned_conditions", [])
	if not warned is Array:
		errors.append("voyage warnings are not a list")
		return null
	for id: Variant in warned:
		if not id is String:
			errors.append("voyage warning id is invalid")
			return null
		voyage.warned_conditions.append(StringName(id))
	# Captain's Log fields (Iteration 006). A voyage saved before then starts
	# from what is certain: it left the course's origin, has sailed at least
	# its progress, and its earlier weather and damage are unknown.
	if data.has("sailed_nm"):
		var departure_position: Variant = PlannedRoute._point_from(data.get("departure_position"))
		var log_fields_ok := data.get("departure_port_id") is String and departure_position != null \
			and _is_number(data.get("sailed_nm")) and float(data.sailed_nm) >= 0.0 \
			and _is_number(data.get("worst_hazard")) and _is_number(data.get("damage_percent")) \
			and data.get("fully_recorded") is bool
		if not log_fields_ok:
			errors.append("voyage log data is invalid")
			return null
		voyage.departure_port_id = StringName(data.departure_port_id)
		voyage.departure_position = departure_position
		voyage.sailed_nm = float(data.sailed_nm)
		voyage.worst_hazard = int(data.worst_hazard)
		voyage.damage_percent = float(data.damage_percent)
		voyage.fully_recorded = data.fully_recorded
	else:
		voyage.departure_port_id = voyage.route.origin_port_id
		voyage.departure_position = voyage.route.origin_position
		voyage.sailed_nm = voyage.progress_nm
		voyage.fully_recorded = false
	# Anchorage waypoints (Iteration 18): optional.
	var holding: Variant = data.get("holding_at", -1)
	var done: Variant = data.get("anchorages_done", [])
	if not _is_number(holding) or int(holding) < -1 or int(holding) >= voyage.route.waypoints.size() or not done is Array:
		errors.append("voyage anchorage data is invalid")
		return null
	voyage.holding_at = int(holding)
	for value: Variant in done:
		if not _is_number(value) or int(value) < 0 or int(value) >= voyage.route.waypoints.size():
			errors.append("voyage anchorage data is invalid")
			return null
		voyage.anchorages_done.append(int(value))
	voyage.standby_until = maxf(float(data.standby_until), 0.0) if _is_number(data.get("standby_until")) else 0.0
	# Tacking (I027): optional; a voyage saved before sails its line.
	var course: Variant = data.get("course", {})
	if course is Dictionary:
		var side: Variant = course.get("tack_side", 0)
		var cross: Variant = course.get("cross_track_nm", 0.0)
		if _is_number(side) and int(side) in [-1, 0, 1] and _is_number(cross) and absf(float(cross)) <= 60.0:
			voyage.tack_side = int(side)
			voyage.cross_track_nm = float(cross)
			for key: String in ["heading_offset_deg", "tack_since", "tack_loss_left_s", "manual_tack_until"]:
				if _is_number(course.get(key)):
					voyage.set(key, float(course[key]))
			for key: String in ["tack_count", "course_leg"]:
				if _is_number(course.get(key)):
					voyage.set(key, int(course[key]))
			voyage.heading_offset_deg = clampf(voyage.heading_offset_deg, -90.0, 90.0)
			voyage.tack_loss_left_s = clampf(voyage.tack_loss_left_s, 0.0, 600.0)
	return voyage


static func _is_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
