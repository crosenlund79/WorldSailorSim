class_name WorldChronicle
extends RefCounted
## The world's shared history (I028 Tier 5): one ledger of events about the
## world's travellers (data/world/travellers.json) - departures, arrivals,
## expeditions announced and completed, books published, meetings - plus the
## Captain's own published works and notable voyages. Every view of the world
## reads it: the Traveller Network's posts, the yacht directory, Sails &
## Sights, renown and the rankings, encounters and invitations. Nothing keeps
## a history of its own.
##
## Sparse, seeded and event-driven: the ledger is extended forward to the
## present (advance) a day at a time, deterministically from the game's seed
## and what is already written; nothing is ever rewritten. A yacht is in one
## harbour or on one leg at a time; a leg lasts its distance at the yacht's
## speed (with a margin for the weather), so no yacht is in two places and no
## ocean is crossed impossibly fast. Expeditions are authored (their stops),
## timed by the same rules.

const DATA_PATH := "res://data/world/travellers.json"
const DAY := 86400.0
const CAPTAIN := "captain"
## A passage takes this much longer than the straight distance at cruising speed.
const ROUTE_FACTOR := 1.3
## Days a yacht stays in harbour between legs (random in this range).
const STAY_DAYS := [3.0, 9.0]
const LEG_NM := [40.0, 650.0]
## A notable traveller publishes something about this often (days).
const BOOK_EVERY_DAYS := 150.0
## Attention fades by half in this many days.
const ATTENTION_HALF_LIFE := 45.0

static var _data: Dictionary


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_data = parsed if parsed is Dictionary else {}
	return _data


static func traveller(id: String) -> Dictionary:
	if id == CAPTAIN:
		return {"id": CAPTAIN, "name": GameSession.get_captain_name() if GameSession.get_captain_name() != "" else Loc.t("You"), "role": "sailor"}
	for t: Dictionary in data().get("travellers", []):
		if t.id == id:
			return t
	var pop := population()
	return pop.get(id, {})


static func yacht(id: String) -> Dictionary:
	for y: Dictionary in data().get("yachts", []):
		if y.id == id:
			return y
	return {}


static func skipper_of(yacht_id: String) -> Dictionary:
	for t: Dictionary in data().get("travellers", []):
		if t.get("yacht", "") == yacht_id:
			return t
	return {}


static var _population: Dictionary


## The larger, lightweight ranked population: id -> {"id", "name", "role", "renown"} (deterministic).
static func population() -> Dictionary:
	if _population.is_empty():
		var p: Dictionary = data().get("population", {})
		var rng := RandomNumberGenerator.new()
		rng.seed = 280028
		var given: Array = p.get("given", [])
		var family: Array = p.get("family", [])
		var roles: Array = p.get("roles", [])
		if given.is_empty() or family.is_empty() or roles.is_empty():
			return _population
		var span: Array = p.get("renown", [20, 300])
		for i in int(p.get("count", 0)):
			var id := "p%d" % i
			_population[id] = {"id": id, "name": "%s %s" % [given[rng.randi() % given.size()], family[rng.randi() % family.size()]],
				"role": roles[rng.randi() % roles.size()], "renown": rng.randi_range(int(span[0]), int(span[1]))}
	return _population


# --- Advancing the ledger ---------------------------------------------------------

## Extends the ledger by every whole day up to `now` (and starts the world the
## first time). Returns the new events.
static func advance(world: WorldState, now: float, seed: int) -> Array:
	var added: Array = []
	if world.started_at <= 0.0:
		world.started_at = now
		world.generated_until = now
		for t: Dictionary in data().get("travellers", []):
			world.renown[String(t.id)] = int(world.renown.get(String(t.id), 0)) + int(t.renown)
			if String(t.get("yacht", "")) != "":
				world.yachts[String(t.yacht)] = {"port": String(t.home), "leg": {}, "next_depart": now + _days(seed, String(t.yacht), 0) * DAY,
					"expedition": "", "stop": 0, "report": {"t": now, "port": String(t.home), "status": "in_port"}}
		for id: String in population():
			world.renown[id] = int(world.renown.get(id, 0)) + int(population()[id].renown)
	# Whole days from the world's start only, so the history never depends on
	# how often it is asked (a day's news is written when the day is over).
	var t := world.generated_until
	while t + DAY <= now:
		var step := t + DAY
		added.append_array(_expeditions(world, t, step))
		for yacht_id: String in _sorted(world.yachts.keys()):
			added.append_array(_advance_yacht(world, yacht_id, step, seed))
		added.append_array(_books(world, t, step, seed))
		added.append_array(_population_news(world, t, step, seed))
		t = step
	world.generated_until = t
	return added


static func _sorted(keys: Array) -> Array:
	var copy := keys.duplicate()
	copy.sort()
	return copy


static func _days(seed: int, key: String, n: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d|%s|%d|stay" % [seed, key, n])
	return rng.randf_range(STAY_DAYS[0], STAY_DAYS[1])


static func _port(id: String) -> PortData:
	return PortCatalog.get_default().get_port(StringName(id))


static func leg_seconds(from: String, to: String, speed_kn: float) -> float:
	var a := _port(from)
	var b := _port(to)
	if a == null or b == null:
		return DAY
	return GeoMath.distance_nm(a.get_geo_position(), b.get_geo_position()) * ROUTE_FACTOR / maxf(speed_kn, 3.0) * 3600.0


static func _advance_yacht(world: WorldState, yacht_id: String, until: float, seed: int) -> Array:
	var added: Array = []
	var st: Dictionary = world.yachts[yacht_id]
	var info := yacht(yacht_id)
	var skipper := skipper_of(yacht_id)
	var guard := 0
	while guard < 6:
		guard += 1
		var leg: Dictionary = st.leg
		if not leg.is_empty():
			if float(leg.arrive) > until:
				break
			st.port = String(leg.to)
			st.leg = {}
			var crew: Array = leg.get("crew", [skipper.get("id", "")])
			var nm := GeoMath.distance_nm(_port(String(leg.from)).get_geo_position(), _port(String(leg.to)).get_geo_position())
			var deltas := {}
			for id: Variant in crew:
				deltas[String(id)] = 1 + int(nm / 150.0)
			var expedition := String(st.get("expedition", ""))
			var arrival := {"t": float(leg.arrive), "kind": "arrive", "who": crew, "yacht": yacht_id, "from": String(leg.from), "port": String(leg.to),
				"nm": roundi(nm), "renown": deltas, "attention": 4 + int(nm / 100.0), "expedition": expedition}
			if expedition != "":
				var exp := _expedition(expedition)
				var stops: Array = exp.stops
				# The stop reached is the harbour itself (a leg to the start is not a stop sailed).
				var reached := stops.find(String(leg.to))
				if reached > int(st.stop) or (reached == 0 and int(st.stop) == 0):
					st.stop = reached
					st.started = true
				if bool(st.get("started", false)) and String(leg.to) == String(stops.back()):
					arrival.kind = "expedition_complete"
					for id: Variant in crew:
						deltas[String(id)] = int(deltas[String(id)]) + int(exp.get("renown", 40))
					arrival.attention = 30
					st.expedition = ""
					st.started = false
			added.append(world.add_event(arrival))
			st.report = {"t": float(leg.arrive), "port": String(leg.to), "status": "in_port"}
			st.next_depart = float(leg.arrive) + _days(seed, yacht_id, world.seq) * DAY
			continue
		if float(st.next_depart) > until:
			break
		var depart := float(st.next_depart)
		var to := _next_destination(world, yacht_id, st, seed)
		if to == "":
			st.next_depart = depart + 3.0 * DAY
			break
		var crew2: Array = [skipper.get("id", "")]
		var expedition_id := String(st.get("expedition", ""))
		if expedition_id != "":
			crew2 = _expedition(expedition_id).get("crew", crew2)
		var seconds := leg_seconds(String(st.port), to, float(info.get("speed", 5.5)))
		st.leg = {"from": String(st.port), "to": to, "depart": depart, "arrive": depart + seconds, "crew": crew2}
		added.append(world.add_event({"t": depart, "kind": "depart", "who": crew2, "yacht": yacht_id, "from": String(st.port), "port": String(st.port),
			"to": to, "eta": depart + seconds, "renown": {}, "attention": 2, "expedition": expedition_id}))
		st.report = {"t": depart, "port": String(st.port), "status": "departed", "to": to}
	world.yachts[yacht_id] = st
	return added


static func _next_destination(world: WorldState, yacht_id: String, st: Dictionary, seed: int) -> String:
	var expedition := String(st.get("expedition", ""))
	if expedition != "":
		var stops: Array = _expedition(expedition).get("stops", [])
		var i := int(st.get("stop", 0))
		if String(st.port) != String(stops[i]):
			return String(stops[i])  # sailing to where the expedition begins (or resumes)
		return String(stops[mini(i + 1, stops.size() - 1)])
	var info := yacht(yacht_id)
	var regions: Array = info.get("regions", [])
	var here := _port(String(st.port))
	if here == null:
		return ""
	var options: Array[String] = []
	for port in PortCatalog.get_default().ports:
		if port.id == here.id or not port.region in regions:
			continue
		var nm := GeoMath.distance_nm(here.get_geo_position(), port.get_geo_position())
		if nm >= LEG_NM[0] and nm <= LEG_NM[1]:
			options.append(String(port.id))
	if options.is_empty():
		return ""
	options.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d|%s|%d|dest" % [seed, yacht_id, world.seq])
	return options[rng.randi() % options.size()]


static func _expedition(id: String) -> Dictionary:
	for e: Dictionary in data().get("expeditions", []):
		if e.id == id:
			return e
	return {}


static func _expeditions(world: WorldState, from_t: float, to_t: float) -> Array:
	var added: Array = []
	for e: Dictionary in data().get("expeditions", []):
		var announce := world.started_at + float(e.announce_day) * DAY
		if announce > from_t and announce <= to_t:
			var stops: Array = e.stops
			added.append(world.add_event({"t": announce, "kind": "expedition_announced", "who": e.crew, "yacht": e.yacht, "port": String(stops[0]),
				"to": String(stops.back()), "expedition": e.id, "renown": {}, "attention": 12, "text": e.get("text", "")}))
		var start := world.started_at + float(e.depart_day) * DAY
		if start > from_t and start <= to_t and world.yachts.has(String(e.yacht)):
			var st: Dictionary = world.yachts[String(e.yacht)]
			st.expedition = String(e.id)
			st.stop = 0
			st.started = String(st.port) == String((e.stops as Array)[0]) and (st.leg as Dictionary).is_empty()
			if (st.leg as Dictionary).is_empty():
				st.next_depart = start
			world.yachts[String(e.yacht)] = st
	return added


static func _books(world: WorldState, from_t: float, to_t: float, seed: int) -> Array:
	var added: Array = []
	for t: Dictionary in data().get("travellers", []):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%d|%s|%d|book" % [seed, t.id, floori(to_t / DAY)])
		var chance := (to_t - from_t) / DAY / BOOK_EVERY_DAYS * (2.0 if t.role in ["writer", "photographer"] else 0.6)
		if rng.randf() < chance:
			added.append(world.add_event({"t": from_t + rng.randf() * (to_t - from_t), "kind": "book", "who": [t.id], "renown": {String(t.id): 12},
				"attention": 10, "title_seed": rng.randi() % 1000, "role": t.role}))
	return added


static func _population_news(world: WorldState, from_t: float, to_t: float, seed: int) -> Array:
	# A handful of the wider population's own small accomplishments each day,
	# so their standing moves with something real (never towards the Captain).
	var added: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d|pop|%d" % [seed, floori(to_t / DAY)])
	var count := population().size()
	if count == 0:
		return added
	for i in 2:
		if rng.randf() < 0.45:
			var id := "p%d" % (rng.randi() % count)
			added.append(world.add_event({"t": from_t + rng.randf() * (to_t - from_t), "kind": "accomplishment", "who": [id],
				"renown": {id: rng.randi_range(2, 8)}, "attention": 3, "minor": true}))
	return added


## The Captain in the world's history: a published work, a notable voyage, a
## dream fulfilled for a passenger.
static func add_captain_event(world: WorldState, kind: String, now: float, details: Dictionary, renown_delta: int, attention: int) -> Dictionary:
	var event := {"t": now, "kind": kind, "who": [CAPTAIN], "renown": {CAPTAIN: renown_delta}, "attention": attention}
	event.merge(details, true)
	return world.add_event(event)


# --- Reading it -------------------------------------------------------------------

## Where a yacht is at `now`: {"status": in_port/under_way, "port", "from", "to", "geo", "progress"}.
static func yacht_position(world: WorldState, yacht_id: String, now: float) -> Dictionary:
	var st: Dictionary = world.yachts.get(yacht_id, {})
	if st.is_empty():
		return {}
	var leg: Dictionary = st.leg
	if not leg.is_empty() and now >= float(leg.depart) and now < float(leg.arrive):
		var a := _port(String(leg.from))
		var b := _port(String(leg.to))
		var f := (now - float(leg.depart)) / maxf(float(leg.arrive) - float(leg.depart), 1.0)
		return {"status": "under_way", "from": leg.from, "to": leg.to, "progress": f, "geo": GeoMath.rhumb_interpolate(a.get_geo_position(), b.get_geo_position(), f)}
	var port := _port(String(st.port))
	return {"status": "in_port", "port": st.port, "geo": port.get_geo_position() if port else Vector2.ZERO}


## A person's renown now: lasting (everything earned) plus attention (recent
## events, fading). Deterministic for the ledger and the time.
static func renown_of(world: WorldState, id: String, now: float, captain_lasting := 0) -> int:
	var lasting := captain_lasting if id == CAPTAIN else int(world.renown.get(id, 0))
	var attention := 0.0
	for e: Dictionary in world.events:
		if id in (e.get("who", []) as Array) and float(e.t) <= now:
			attention += float(e.get("attention", 0)) * pow(0.5, (now - float(e.t)) / DAY / ATTENTION_HALF_LIFE)
	return lasting + roundi(attention)


## Everyone ranked at `now`: [{"id", "name", "role", "renown", "rank"}], by
## renown, ties by id (stable). `captain_lasting`: the Captain's own lasting
## renown (the game's renown total, which already holds every award; the
## Captain's events in the ledger add only their fading attention).
static func rankings(world: WorldState, now: float, captain_lasting: int) -> Array:
	var rows: Array = []
	var ids: Array = []
	for t: Dictionary in data().get("travellers", []):
		ids.append(String(t.id))
	ids.append_array(population().keys())
	ids.append(CAPTAIN)
	var attention := {}  # one pass over the ledger for everyone
	for e: Dictionary in world.events:
		if float(e.t) > now or int(e.get("attention", 0)) == 0:
			continue
		var fade := float(e.attention) * pow(0.5, (now - float(e.t)) / DAY / ATTENTION_HALF_LIFE)
		for who: Variant in (e.get("who", []) as Array):
			attention[String(who)] = float(attention.get(String(who), 0.0)) + fade
	for id: String in ids:
		var t := traveller(id)
		var lasting := captain_lasting if id == CAPTAIN else int(world.renown.get(id, 0))
		var score := lasting + roundi(float(attention.get(id, 0.0)))
		rows.append({"id": id, "name": String(t.get("name", id)), "role": String(t.get("role", "sailor")), "renown": score})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.renown) > int(b.renown) if int(a.renown) != int(b.renown) else String(a.id) < String(b.id))
	for i in rows.size():
		rows[i].rank = i + 1
	return rows


static func rank_of(world: WorldState, id: String, now: float, captain_lasting: int) -> int:
	for row: Dictionary in rankings(world, now, captain_lasting):
		if row.id == id:
			return int(row.rank)
	return 0
