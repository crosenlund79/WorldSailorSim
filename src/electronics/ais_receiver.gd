class_name AisReceiver
extends RefCounted
## AIS preparation (Between Horizons, I027 Tier 4): the integration surface
## for local AIS contacts, so I028 (and a future cockpit display) can read
## them without inventing a second traffic world. Audit of I026: the radar
## panel and the traffic warnings already read TrafficModel's plausible,
## deterministic local vessels; there was no AIS. This adds no instrument and
## no screen.
##
## A contact is one of TrafficModel's vessels within VHF reach of the boat,
## as an AIS receiver would list it: a stable fictional MMSI, its name and
## kind, class A (ships) or B (small craft), course and speed over ground,
## range and bearing from the boat, and the closest point of approach (CPA)
## and its time (TCPA) against the boat's own course and speed. Local only:
## never more than RANGE_NM, never a worldwide tracker (the searchable yacht
## directory belongs to I028). Pure and static; nothing is saved.

## A small yacht's VHF aerial hears AIS this far (nm).
const RANGE_NM := 20.0
## MMSIs are fictional: a nine-digit number from a block no real station uses.
const MMSI_BASE := 990000000
const CLASS_A := "A"
const CLASS_B := "B"
## TrafficModel kinds that carry class A transponders (the rest: class B).
const CLASS_A_KINDS: Array[StringName] = [&"cargo", &"tanker", &"ferry"]


## The contacts within `range_nm` (at most RANGE_NM) of the boat now, nearest
## first. Empty without a game.
static func contacts(range_nm := RANGE_NM) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not GameSession.is_active():
		return out
	var own_course := Simulation.get_current_heading() if GameSession.is_underway() else 0.0
	var own_speed := GameSession.get_vessel_speed_kn() if GameSession.is_underway() else 0.0
	return contacts_at(GameSession.get_vessel_position(), GameSession.get_game_time(), GameSession.get_wind_seed(),
		own_course, own_speed, range_nm)


## The same for any position, time and own motion (pure: the same inputs
## always give the same contacts).
static func contacts_at(geo: Vector2, time: float, seed: int, own_course: float, own_speed_kn: float,
		range_nm := RANGE_NM) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for vessel in TrafficModel.get_default().vessels_near(geo, time, seed, minf(range_nm, RANGE_NM)):
		var offset: Vector2 = vessel.offset_nm  # east, north of the boat (nm)
		var closest := approach(offset, own_course, own_speed_kn, float(vessel.course), float(vessel.speed_kn))
		out.append({"mmsi": mmsi(String(vessel.id)), "name": String(vessel.name), "kind": String(vessel.kind),
			"class": CLASS_A if StringName(vessel.kind) in CLASS_A_KINDS else CLASS_B,
			"geo": vessel.geo, "cog": float(vessel.course), "sog_kn": float(vessel.speed_kn),
			"range_nm": offset.length(), "bearing": fposmod(rad_to_deg(atan2(offset.x, offset.y)), 360.0),
			"cpa_nm": closest.x, "tcpa_min": closest.y})
	return out


## The closest point of approach of a vessel `offset` (east, north, nm) from
## the boat: Vector2(CPA in nm, TCPA in minutes; a negative TCPA means it is
## already past, and the CPA is then the distance now).
static func approach(offset: Vector2, own_course: float, own_speed_kn: float, course: float, speed_kn: float) -> Vector2:
	var relative := _velocity(course, speed_kn) - _velocity(own_course, own_speed_kn)
	var closing := relative.length_squared()
	var tcpa_h := -offset.dot(relative) / closing if closing > 1e-9 else 0.0
	return Vector2((offset + relative * maxf(tcpa_h, 0.0)).length(), tcpa_h * 60.0)


## A vessel's fictional MMSI: stable for its traffic id.
static func mmsi(traffic_id: String) -> int:
	return MMSI_BASE + posmod(hash(traffic_id), 10000000)


## A course (degrees true) and speed as an east/north velocity (knots).
static func _velocity(course_deg: float, speed_kn: float) -> Vector2:
	var a := deg_to_rad(course_deg)
	return Vector2(sin(a), cos(a)) * speed_kn
