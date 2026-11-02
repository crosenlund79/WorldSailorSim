class_name Marketplace
extends RefCounted
## The passage trade's rules (I028 Tier 1): building an offer from the chart's
## authoritative route (SeaRouter, PassagePlan), fares, capacity leg by leg,
## travellers' requests, the competing skippers and negotiation. Pure: it
## reads the game and the PassageBook it is given and returns new data;
## GameSession keeps it and moves the money.
##
## An offer is the Captain's planned voyage as stops [A, B, C, ...]: each leg
## (A to B, B to C) is planned by SeaRouter and timed by PassagePlan (weather,
## engine, the boat's speed), so a passage on the laptop is the passage the
## chart would sail. A booking reserves the legs from its embarkation stop to
## its disembarkation stop; capacity is checked on every leg it overlaps.

const SKIPPERS_PATH := "res://data/passengers/skippers.json"
## The going rate: euros per nautical mile and person on a simple boat, by comfort.
const BASE_RATE := 1.4
const COMFORT_FACTOR := {"simple": 1.0, "comfortable": 1.25, "spacious": 1.6}
## A night aboard (per person) and the least a leg costs (per person).
const NIGHT_FEE := 30
const MIN_FARE := 35
## A leg longer than this is sailed through a night (the guests sleep aboard).
const OVERNIGHT_LEG_H := 10.0
## Planned time in an intermediate harbour, and the departure window.
const STOPOVER_H := 14.0
const WINDOW_H := 24.0
## Harbours this close to the planned path can be added as stops.
const STOP_CORRIDOR_NM := 15.0
const MAX_STOPS := 5
## Share of the fare paid on booking (refunded if the Captain cancels).
const DEPOSIT_SHARE := 0.3
## How long a request waits for an answer.
const REQUEST_HOURS := 24.0
## A request asks more than this over the traveller's limit: a counter-offer is refused outright.
const COUNTER_LIMIT := 1.15

static var _skippers: Array = []


static func skippers() -> Array:
	if _skippers.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SKIPPERS_PATH))
		_skippers = parsed.get("skippers", []) if parsed is Dictionary else []
	return _skippers


static func get_skipper(id: String) -> Dictionary:
	for s: Dictionary in skippers():
		if s.id == id:
			return s
	return {}


# --- Fares ------------------------------------------------------------------------

## Euros per nautical mile and person for a boat (its comfort).
static func going_rate(vessel_id: StringName) -> float:
	return snappedf(BASE_RATE * float(COMFORT_FACTOR.get(String(Accommodation.comfort_tier(vessel_id)), 1.0)), 0.05)


static func leg_nights(seconds: float) -> int:
	return floori(seconds / 86400.0) + (1 if fmod(seconds, 86400.0) > OVERNIGHT_LEG_H * 3600.0 else 0)


## The fare for `size` people on legs [from, to) of an offer at its rate.
static func fare(offer: Dictionary, from: int, to: int, size: int, rate := -1.0) -> int:
	rate = float(offer.rate) if rate < 0.0 else rate
	var total := 0.0
	var nights := 0
	for i in range(from, to):
		total += float(offer.leg_nm[i]) * rate
		nights += leg_nights(float(offer.leg_s[i]))
	var per_person := maxf(total + nights * NIGHT_FEE, MIN_FARE)
	return int(snappedf(per_person * size, 5.0))


static func distance(offer: Dictionary, from: int, to: int) -> float:
	var nm := 0.0
	for i in range(from, to):
		nm += float(offer.leg_nm[i])
	return nm


static func nights(offer: Dictionary, from: int, to: int) -> int:
	var n := 0
	for i in range(from, to):
		n += leg_nights(float(offer.leg_s[i]))
	return n


# --- Offers -----------------------------------------------------------------------

## Harbours within STOP_CORRIDOR_NM of a planned route's path, in order along
## it (not its origin or destination): the stops an offer may add.
static func candidate_stops(route: PlannedRoute) -> Array[StringName]:
	var found: Array[StringName] = []
	if route == null or not route.has_path():
		return found
	var path := route.path
	var box := Rect2(path[0], Vector2.ZERO)
	for p in path:
		box = box.expand(p)
	var grow := STOP_CORRIDOR_NM / 60.0 * 2.0
	var along := {}
	for port in PortCatalog.get_default().ports_in_rect(box.grow(grow)):
		if port.id == route.origin_port_id or port.id == route.destination_port_id:
			continue
		var geo := port.get_geo_position()
		var best := INF
		var walked := 0.0
		var at := 0.0
		for i in range(1, path.size()):
			var d := GeoMath.distance_to_segment_nm(geo, path[i - 1], path[i])
			if d < best:
				best = d
				at = walked + GeoMath.distance_nm(path[i - 1], geo)
			walked += GeoMath.distance_nm(path[i - 1], path[i])
		if best <= STOP_CORRIDOR_NM:
			along[port.id] = at
			found.append(port.id)
	found.sort_custom(func(a: StringName, b: StringName) -> bool: return along[a] < along[b])
	return found


## A new offer for the stops (at least two harbours, in sailing order), leaving
## from the first one in the window from `depart_after`. Each leg is planned
## and timed on the real chart. {"error"} when a leg cannot be sailed.
static func build_offer(id: String, stops: Array, vessel_id: StringName, depart_after: float, rate: float, now: float) -> Dictionary:
	if stops.size() < 2:
		return {"error": Loc.t("Choose where the passage goes.")}
	var router := SeaRouter.get_default()
	var catalog := PortCatalog.get_default()
	var leg_nm: Array = []
	var leg_s: Array = []
	var kinds: Array = []
	var arrive: Array = [depart_after]
	var depart: Array = [depart_after]
	var clock := depart_after
	for i in range(1, stops.size()):
		var a := catalog.get_port(StringName(stops[i - 1]))
		var b := catalog.get_port(StringName(stops[i]))
		if a == null or b == null:
			return {"error": Loc.t("A stop is not a harbour.")}
		var result := router.plan_route(a.id, a.get_geo_position(), [] as Array[Vector2], b.id)
		if not result.is_ok():
			return {"error": Loc.t("No sea route from %s to %s.") % [a.display_name, b.display_name]}
		var plan := PassagePlan.from_route(result.route, clock, WINDOW_H)
		if not Accommodation.suits_passage(vessel_id, StringName(plan.feasibility.kind)):
			return {"error": Loc.t("The leg from %s to %s is a %s passage, more than this boat is fitted for.") % [a.display_name, b.display_name,
				Accommodation.passage_short(StringName(plan.feasibility.kind))]}
		leg_nm.append(snappedf(plan.distance_nm, 0.1))
		leg_s.append(roundf(plan.estimated_seconds))
		kinds.append(String(plan.feasibility.kind))
		clock += plan.estimated_seconds
		arrive.append(clock)
		clock += STOPOVER_H * 3600.0
		depart.append(clock)
	return {"id": id, "status": PassageBook.STATUS_PUBLISHED, "vessel": String(vessel_id), "stops": stops.duplicate(),
		"leg_nm": leg_nm, "leg_s": leg_s, "kinds": kinds, "arrive": arrive, "depart": depart,
		"depart_after": depart_after, "depart_before": depart_after + WINDOW_H * 3600.0, "rate": rate,
		"published_at": now, "stop_index": 0, "departed": [], "arrived": [], "requests_made": false}


## People aboard on leg `leg` of an offer (confirmed or aboard bookings), and
## how many of them have a private cabin.
static func occupancy(book: PassageBook, offer_id: String, leg: int) -> Vector2i:
	var persons := 0
	var private := 0
	for booking: Dictionary in book.bookings_for_offer(offer_id):
		if int(booking.from) <= leg and leg < int(booking.to):
			persons += int(booking.size)
			private += 1 if booking.get("private", false) else 0
	return Vector2i(persons, private)


## "" when `size` more people (with a private cabin if `private`) fit on every
## leg in [from, to), else why not. Legs through a night need a bed each.
static func capacity_problem(book: PassageBook, offer: Dictionary, from: int, to: int, size: int, private: bool) -> String:
	var vessel := StringName(offer.vessel)
	for leg in range(from, to):
		var used := occupancy(book, String(offer.id), leg)
		var overnight := leg_nights(float(offer.leg_s[leg])) > 0
		var room := Accommodation.overnight_guest_count(vessel) if overnight else Accommodation.safe_guest_count(vessel)
		if used.x + size > room:
			return Loc.t("No room on the leg to %s: %d of %d places taken.") % [_port_name(offer.stops[leg + 1]), used.x, room]
		if private and used.y + 1 > Accommodation.private_guest_cabins(vessel):
			return Loc.t("No private cabin free on the leg to %s.") % _port_name(offer.stops[leg + 1])
	return ""


static func _port_name(id: Variant) -> String:
	var port := PortCatalog.get_default().get_port(StringName(id))
	return port.display_name if port else String(id)


# --- Requests and the competing skippers ------------------------------------------

## The best competing skipper's offer for this traveller on legs [from, to)
## of an offer (seeded by the week and the route, never simulated), or {}.
static func best_rival(traveller: Dictionary, offer: Dictionary, from: int, to: int, now: float, region: String) -> Dictionary:
	var week := floori(now / (7.0 * 86400.0))
	var best := {}
	for s: Dictionary in skippers():
		var regions: Array = s.regions
		if not ("any" in regions or region in regions):
			continue
		# Is this skipper sailing this way this week? About a third of the time.
		var roll := hash("%s|%s|%s|%d" % [s.id, offer.stops[from], offer.stops[to], week]) % 100
		if roll >= 34 or int(s.berths) < int(traveller.size):
			continue
		var rival_fare := int(snappedf(fare(offer, from, to, int(traveller.size), BASE_RATE * float(s.price)), 5.0))
		var score := appeal(traveller, rival_fare, from, to, offer, String(s.comfort), int(s.private_cabins) > 0, bool(s.pets), [], float(s.rating))
		if best.is_empty() or score > float(best.score):
			best = {"skipper": s.id, "fare": rival_fare, "score": score}
	return best


## How much a traveller likes a passage (higher is better): the fare against
## their budget, comfort, privacy, animals aboard and the skipper's reviews.
static func appeal(traveller: Dictionary, asked: int, from: int, to: int, offer: Dictionary, comfort: String, private_cabin: bool,
		pets_welcome: bool, pets_aboard: Array, rating: float) -> float:
	var budget := maxf(fare(offer, from, to, int(traveller.size), float(traveller.budget)), 1.0)
	var score := 1.0 - (float(asked) - budget) / budget  # 1 at their budget, more when cheaper
	var want := Accommodation.COMFORT_ORDER.find(StringName(traveller.comfort))
	var have := Accommodation.COMFORT_ORDER.find(StringName(comfort))
	score += 0.15 * clampi(have - want, -2, 1)
	if traveller.privacy == "requires" and not private_cabin:
		return -10.0
	if traveller.privacy == "prefers":
		score += 0.1 if private_cabin else -0.1
	if not Travellers.tolerates_pets(traveller, pets_aboard):
		return -10.0
	if traveller.pets == "likes" and (pets_welcome or not pets_aboard.is_empty()):
		score += 0.15
	score += 0.08 * (rating - 4.0) if rating > 0.0 else 0.0
	return score


## New requests for a published offer: travellers who saw it, in the next day
## or so (each appears at its own time). Deterministic for the offer and seed.
## Travellers who prefer a competing skipper's passage are kept as "lost", with
## the reason, so the Captain sees why. `pets` are the kinds aboard.
static func generate_requests(book: PassageBook, offer: Dictionary, now: float, seed: int, pets: Array, rating: float, region: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%d" % [offer.id, seed])
	var stops: Array = offer.stops
	var demand := 0.0
	for id: Variant in stops:
		var port := PortCatalog.get_default().get_port(StringName(id))
		demand += {1: 1.2, 2: 0.8, 3: 0.5}.get(port.importance if port else 3, 0.5)
	# Asking above the going rate thins the interest; below it, more people ask.
	var price_ratio := float(offer.rate) / maxf(going_rate(StringName(offer.vessel)), 0.1)
	var count := clampi(roundi(demand * rng.randf_range(0.8, 1.6) / clampf(price_ratio, 0.6, 2.0)), 1, 7)
	var made: Array = []
	var vessel := StringName(offer.vessel)
	var room := maxi(Accommodation.safe_guest_count(vessel), 1)
	for n in count:
		var from := 0
		var to := stops.size() - 1
		if stops.size() > 2 and rng.randf() < 0.55:
			from = rng.randi_range(0, stops.size() - 2)
			to = rng.randi_range(from + 1, stops.size() - 1)
		var tid := book.new_id("t")
		var traveller := Travellers.make(rng.randi(), tid, room, String(stops[from]))
		var private: bool = traveller.privacy == "requires"
		var budget := fare(offer, from, to, int(traveller.size), float(traveller.budget))
		var asked := fare(offer, from, to, int(traveller.size))
		var request := {"id": book.new_id("r"), "offer": offer.id, "traveller": tid, "size": int(traveller.size), "from": from, "to": to,
			"private": private, "asked": asked, "offered": mini(asked, budget), "limit": int(budget * rng.randf_range(1.0, 1.2)),
			"appear_at": now + rng.randf_range(0.3, maxf((float(offer.depart_after) - now) / 3600.0 - 3.0, 1.0)) * 3600.0, "status": PassageBook.REQUEST_PENDING, "round": 0, "note": ""}
		request.expires_at = float(request.appear_at) + REQUEST_HOURS * 3600.0
		if not Travellers.tolerates_pets(traveller, pets):
			continue  # an allergy to the animals aboard: they never ask
		var ours := appeal(traveller, asked, from, to, offer, String(Accommodation.comfort_tier(vessel)),
			Accommodation.private_guest_cabins(vessel) > 0, true, pets, rating)
		var rival := best_rival(traveller, offer, from, to, now, region)
		if ours < -1.0:
			continue  # the boat cannot give them what they need (a private cabin)
		if not rival.is_empty() and float(rival.score) > ours + 0.12:
			request.status = PassageBook.REQUEST_LOST
			request.rival = rival.skipper
			request.rival_fare = rival.fare
			request.note = _lost_reason(traveller, asked, int(rival.fare), get_skipper(String(rival.skipper)), pets)
		made.append({"request": request, "traveller": traveller})
	return made


static func _lost_reason(traveller: Dictionary, ours: int, theirs: int, skipper: Dictionary, pets: Array) -> String:
	if theirs < ours * 0.92:
		return Loc.t("went with %s on %s: cheaper (%s)") % [skipper.name, skipper.yacht, GameSession.format_money(theirs)]
	if traveller.privacy != "shared_ok" and int(skipper.private_cabins) > 0:
		return Loc.t("went with %s on %s: a private cabin") % [skipper.name, skipper.yacht]
	if traveller.pets == "likes" and bool(skipper.pets) and pets.is_empty():
		return Loc.t("went with %s on %s: a ship's dog aboard") % [skipper.name, skipper.yacht]
	return Loc.t("went with %s on %s: better reviews") % [skipper.name, skipper.yacht]


## A traveller's answer to the Captain's price `ask` for a request: accept,
## a counter-offer (once, halfway) or no. {"result": "accept"/"counter"/"decline", "fare"}.
static func answer_counter(request: Dictionary, ask: int) -> Dictionary:
	var limit := int(request.limit)
	if ask <= limit:
		return {"result": "accept", "fare": ask}
	if int(request.round) == 0 and ask <= limit * COUNTER_LIMIT:
		return {"result": "counter", "fare": int(snappedf((limit + int(request.offered)) * 0.5 + (limit - int(request.offered)) * 0.25, 5.0))}
	return {"result": "decline", "fare": 0}


static func deposit_for(fare_eur: int) -> int:
	return int(snappedf(fare_eur * DEPOSIT_SHARE, 5.0))
