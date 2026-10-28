class_name HarbourLife
extends Node2D
## The people of the quay (I026 stage 02, living harbours): a handful of
## townsfolk with small routines, so a harbour feels inhabited.
##
## Deterministic and cheap. Who is about follows from the harbour id, the
## local day and the hour (the authoritative clock, on the harbour's solar
## time): each of a few "slots" has a role and a window of hours that day
## (roster_at). The roster is rebuilt when the quay is built and checked
## again every few real seconds while the Captain watches; nothing is
## simulated while away, so sleeping or a time skip never leaves a backlog -
## the quay simply shows who is about at the new hour.
##
## Roles: walkers with destinations and pauses (a shop window, a bench, the
## quay's edge), shoppers who go into a shop and come out again (only open
## ones), café customers who sit, read or chat (only while the café is
## open), a fisherman with his nets in the morning, a shopkeeper locking up
## at closing time, and a late walker at night. Few or none at night and in
## bad weather; busier in a larger harbour, quiet in a small one
## (PEOPLE_BY_TIER).
##
## Movement is in real time at a walking pace; people keep to the
## promenade's walking line, never linger in a doorway or at the walkway's
## head (QuayLayout.is_in_the_way), have no physics body and step around the
## Captain (AVOID_RADIUS) instead of pushing through. A few nodes, no
## per-frame scans: each person only looks at its own target and the Captain.

const PEOPLE_BY_TIER := {&"small": 3, &"larger": 6, &"major": 8}
## The walking line along the promenade (between the terrace and the
## benches), and how far people spread around it.
const WALK_Y := 318.0
const WALK_SPREAD := 14.0
const SPEED := Vector2(80.0, 110.0)
const AVOID_RADIUS := 70.0
## How often (real seconds) the roster is compared with the clock.
const ROSTER_CHECK := 2.0
## Hours that count as night (only the late walker is about).
const NIGHT_FROM := 22.5
const NIGHT_UNTIL := 5.5

const ROLE_WALKER := &"walker"
const ROLE_SHOPPER := &"shopper"
const ROLE_CAFE := &"cafe"
const ROLE_FISHER := &"fisher"
const ROLE_KEEPER := &"keeper"
const ROLE_LATE := &"late"

var layout: QuayLayout
var port_id: StringName = &""
## The Captain (to step around); set by HarbourFront.
var captain: Node2D
## Café seats taken by someone other than the townsfolk (the Captain).
var reserved_seats := {}
## Weather override for tests: -1 uses the weather at the boat.
var weather_factor_override := -1.0
## The benches along the edge (QuayDrawing), set before setup(): someone
## may sit on one a while, and nobody stands in front of one.
var benches := PackedVector2Array()

var _people := {}
var _check := 0.0
var _last_time := -1.0
## A larger step of game time between two looks is a jump, not watching.
const JUMP_SECONDS := 4000.0  # more than 20× time covers between two looks
var _x_min := 0.0
var _x_max := 0.0


func setup(layout_: QuayLayout, captain_: Node2D) -> void:
	layout = layout_
	port_id = layout.port_id
	captain = captain_
	_x_min = layout.left + 120.0
	if layout.lift != Vector2.ZERO:
		_x_min = maxf(_x_min, layout.lift.y + 60.0)
	_x_max = layout.right - 120.0
	rebuild()


## Who is about now: the roster for the current game time, placed straight
## into what they are doing (no walking in from nowhere after a skip).
func rebuild() -> void:
	for person in _people.values():
		(person as Node).queue_free()
	_people.clear()
	if not GameSession.is_active():
		return
	_last_time = GameSession.get_game_time()
	for entry in roster_at(_last_time):
		_spawn(entry, true)


func get_people() -> Array:
	return _people.values()


func get_person_count() -> int:
	return _people.size()


## How lively the weather lets the quay be: 1 fair, 0.5 windy, 0 in a gale,
## a storm or a thunderstorm.
func weather_factor() -> float:
	if weather_factor_override >= 0.0:
		return weather_factor_override
	var weather := Simulation.get_weather_at_vessel()
	if weather == null:
		return 1.0
	if weather.thunder_active or weather.hazard >= WeatherModel.HAZARD_DANGEROUS or weather.classification in [WeatherModel.CLASS_GALE,
			WeatherModel.CLASS_STORM, WeatherModel.CLASS_THUNDERSTORM, WeatherModel.CLASS_SQUALL, WeatherModel.CLASS_TROPICAL_STORM,
			WeatherModel.CLASS_HURRICANE]:
		return 0.0
	if weather.classification == WeatherModel.CLASS_STRONG_WIND or weather.hazard >= WeatherModel.HAZARD_CAUTION:
		return 0.5
	return 1.0


## How much of the day's company is about at local hour `h` (0..1).
static func activity(h: float) -> float:
	if h < NIGHT_UNTIL or h >= NIGHT_FROM:
		return 0.0
	if h < 8.0:
		return lerpf(0.25, 1.0, (h - NIGHT_UNTIL) / (8.0 - NIGHT_UNTIL))
	if h < 18.0:
		return 1.0
	if h < 20.5:
		return lerpf(1.0, 0.45, (h - 18.0) / 2.5)
	return 0.3


## The roster at game time `time`: [{"key", "role", "seed", "look_seed",
## "business", "seat", "start", "end"}]. Pure: the same harbour and time
## always give the same people.
func roster_at(time: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var h := BusinessHours.local_hours(port_id, time)
	var day := floori((time + BusinessHours.longitude_of(port_id) / 15.0 * 3600.0) / 86400.0)
	var weather := weather_factor()
	var capacity: int = PEOPLE_BY_TIER.get(layout.tier, 5)
	var level := activity(h) * weather
	# The fisherman mends his nets on the quay in the morning (not in bad weather).
	var fisher_rng := _rng("fisher", day)
	if weather > 0.4 and h >= 5.5 and h < 10.5 + fisher_rng.randf_range(0.0, 1.5) and fisher_rng.randf() < 0.8:
		out.append({"key": "fisher:%d" % day, "role": ROLE_FISHER, "seed": fisher_rng.randi(), "look_seed": hash("fisher:%s" % port_id)})
	# Walkers and shoppers: each slot has its window of the day.
	for k in capacity:
		var rng := _rng("slot%d" % k, day)
		var start := rng.randf_range(6.5, 19.5)
		var end := start + rng.randf_range(2.0, 5.0)
		var threshold := rng.randf()
		if h >= start and h < end and threshold < level:
			out.append({"key": "slot%d:%d" % [k, day], "role": ROLE_SHOPPER if rng.randf() < 0.5 else ROLE_WALKER,
				"seed": rng.randi(), "look_seed": rng.randi()})
	# Café customers while the café is open.
	if layout.has_business(QuayLayout.CAFE) and BusinessHours.is_open(QuayLayout.CAFE, port_id, time) and not layout.cafe_seats.is_empty():
		var sitters := clampi(roundi(capacity * 0.5 * level), 0, layout.cafe_seats.size() - 2)
		for k in sitters:
			var rng := _rng("cafe%d" % k, day * 24 + floori(h / 2.0))
			if rng.randf() > 0.8:
				continue
			# Spread over the tables, two at one now and then (they chat).
			var seat := (k * 3) % layout.cafe_seats.size()
			if seat in reserved_seats or _seat_taken(out, seat):
				continue
			out.append({"key": "cafe%d:%d:%d" % [k, day, floori(h / 2.0)], "role": ROLE_CAFE, "seat": seat,
				"seed": rng.randi(), "look_seed": rng.randi()})
	# A shopkeeper locking up, just after closing time.
	for business in layout.get_businesses():
		if not BusinessHours.has_hours(business) or BusinessHours.local_weekday(port_id, time) in BusinessHours.closed_days(business):
			continue
		var close := BusinessHours.hours(business, port_id).y
		if h >= close and h < close + 0.35:
			out.append({"key": "keeper:%s:%d" % [business, day], "role": ROLE_KEEPER, "business": business,
				"seed": hash("%s:%s:%d" % [port_id, business, day]), "look_seed": hash("keeper:%s:%s" % [port_id, business])})
	# A late walker at night, in fair weather.
	var late_rng := _rng("late", day)
	var late_start := 21.0 + late_rng.randf_range(0.0, 1.0)
	if weather >= 1.0 and h >= late_start and h < late_start + 1.2 and late_rng.randf() < 0.75:
		out.append({"key": "late:%d" % day, "role": ROLE_LATE, "seed": late_rng.randi(), "look_seed": late_rng.randi()})
	return out


static func _seat_taken(entries: Array[Dictionary], seat: int) -> bool:
	for entry in entries:
		if int(entry.get("seat", -1)) == seat:
			return true
	return false


func _rng(what: String, day: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%s:%d" % [port_id, what, day])
	return rng


func _process(delta: float) -> void:
	if layout == null:
		return
	_check -= delta
	if _check <= 0.0:
		_check = ROSTER_CHECK
		_update_roster()
	for person: Townsperson in _people.values():
		person.advance(delta)


## Compares who should be about with who is: newcomers arrive (from the
## lane, an end of the quay or a shop door), those whose time is up leave.
func _update_roster() -> void:
	if not GameSession.is_active():
		return
	# A jump in time (waiting for a shop, a dawn or dusk passed under the
	# black): the quay as it is at the new hour, no backlog.
	var now := GameSession.get_game_time()
	if _last_time >= 0.0 and absf(now - _last_time) > JUMP_SECONDS:
		_last_time = now
		rebuild()
		return
	_last_time = now
	var wanted := {}
	for entry in roster_at(GameSession.get_game_time()):
		wanted[entry.key] = entry
	for key: String in _people.keys():
		var person: Townsperson = _people[key]
		if not wanted.has(key) and not person.leaving:
			person.leave()
	for key: String in wanted:
		if not _people.has(key):
			_spawn(wanted[key], false)


func _spawn(entry: Dictionary, settled: bool) -> void:
	var person := Townsperson.new()
	person.name = "Person_%s" % String(entry.key).replace(":", "_")
	person.life = self
	person.entry = entry
	person.look = TownsfolkDrawing.make_look(layout.archetype, int(entry.look_seed))
	_people[entry.key] = person
	add_child(person)
	person.begin(settled)


func _forget(person: Townsperson) -> void:
	_people.erase(person.entry.key)
	person.queue_free()


# --- Places --------------------------------------------------------------------

## A walking point on the promenade at `x`.
func walk_point(x: float, rng: RandomNumberGenerator) -> Vector2:
	return Vector2(clampf(x, _x_min, _x_max), WALK_Y + rng.randf_range(-WALK_SPREAD, WALK_SPREAD))


## Somewhere to pause: by a shop window, at a bench, at the quay's edge
## looking at the boats - never in a doorway or at the walkway's head.
func pause_point(rng: RandomNumberGenerator) -> Vector2:
	for attempt in 8:
		var p: Vector2
		var pick := rng.randi() % 3
		if pick == 0 and not layout.fronts.is_empty():
			var front: Dictionary = layout.fronts[rng.randi() % layout.fronts.size()]
			p = Vector2(rng.randf_range(float(front.x0) + 40.0, float(front.x1) - 40.0), rng.randf_range(115.0, 135.0))
		elif pick == 1:
			p = Vector2(rng.randf_range(_x_min, _x_max), QuayLayout.EDGE_Y - 76.0)
		else:
			p = walk_point(rng.randf_range(_x_min, _x_max), rng)
		p.x = clampf(p.x, _x_min, _x_max)
		if not layout.is_in_the_way(p) and not _near_cafe_tables(p) and not near_bench(p.x, 110.0):
			return p
	return walk_point(rng.randf_range(_x_min, _x_max), rng)


func near_bench(x: float, distance: float) -> bool:
	for bench in benches:
		if absf(bench.x - x) < distance:
			return true
	return false


## A place on a bench (facing the water), or Vector2.INF without one.
func bench_seat(rng: RandomNumberGenerator) -> Vector2:
	var usable: Array[Vector2] = []
	for bench in benches:
		if bench.x > _x_min and bench.x < _x_max:
			usable.append(bench)
	if usable.is_empty():
		return Vector2.INF
	return usable[rng.randi() % usable.size()] + Vector2(rng.randf_range(-45.0, 45.0), -6.0)


func _near_cafe_tables(p: Vector2) -> bool:
	for table in layout.cafe_tables:
		if p.distance_to(table) < 95.0:
			return true
	return false


## Where people come and go: the lane into town, or an end of the quay.
func exit_point(rng: RandomNumberGenerator) -> Vector2:
	var lane := layout.get_front(QuayLayout.LANE)
	if not lane.is_empty() and rng.randf() < 0.6:
		return Vector2(float(lane.door), -30.0)
	return Vector2(_x_min - 260.0 if rng.randf() < 0.5 else _x_max + 260.0, WALK_Y)


## An open business to go into (its door), or Vector2.INF.
func open_door(rng: RandomNumberGenerator) -> Vector2:
	var open: Array[StringName] = []
	for business in layout.get_businesses():
		if business != QuayLayout.BOATYARD and BusinessHours.is_open(business, port_id, GameSession.get_game_time()):
			open.append(business)
	if open.is_empty():
		return Vector2.INF
	var door := layout.door_station(open[rng.randi() % open.size()])
	return Vector2(door.x, 8.0)


## A place along the quay for someone already about: half near where the
## Captain is, half anywhere.
func near_captain_x(rng: RandomNumberGenerator) -> float:
	if captain and rng.randf() < 0.6:
		return captain.position.x + rng.randf_range(-900.0, 900.0)
	return rng.randf_range(_x_min, _x_max)


func get_x_range() -> Vector2:
	return Vector2(_x_min, _x_max)


## One person on the quay: a small state machine in real time.
class Townsperson extends Node2D:
	const WALK := &"walk"
	const PAUSE := &"pause"
	const INSIDE := &"inside"
	const SIT := &"sit"
	const FISH := &"fish"
	const LOCK := &"lock"
	const BENCH := &"bench"

	var life: HarbourLife
	var entry: Dictionary
	var look: Dictionary
	var state: StringName = WALK
	var leaving := false
	var facing := Vector2.DOWN
	var item: StringName = TownsfolkDrawing.ITEM_NONE
	var _path := PackedVector2Array()
	var _wait := 0.0
	var _speed := 90.0
	var _phase := 0.0
	var _swing := 0.0
	var _step := 0
	var _then: StringName = &""
	var _rng := RandomNumberGenerator.new()
	var _time := 0.0
	var _on_bench := false

	func begin(settled: bool) -> void:
		_rng.seed = int(entry.seed)
		_speed = _rng.randf_range(HarbourLife.SPEED.x, HarbourLife.SPEED.y)
		var role: StringName = entry.role
		z_index = 0
		match role:
			HarbourLife.ROLE_CAFE:
				var seat: Dictionary = life.layout.cafe_seats[int(entry.seat)]
				item = TownsfolkDrawing.ITEM_PAPER if _rng.randf() < 0.5 else TownsfolkDrawing.ITEM_CUP
				if settled or int(entry.seat) in life.reserved_seats:
					position = seat.at
					_sit()
				else:
					position = _arrival()
					_go(seat.at, SIT)
			HarbourLife.ROLE_FISHER:
				position = _fisher_spot() if settled else _arrival()
				if settled:
					state = FISH
					facing = Vector2.DOWN
				else:
					_go(_fisher_spot(), FISH)
			HarbourLife.ROLE_KEEPER:
				var door := life.layout.door_station(StringName(entry.business))
				position = Vector2(door.x, 10.0)
				item = TownsfolkDrawing.ITEM_KEYS
				state = LOCK
				facing = Vector2.UP
				_wait = 4.0 if settled else 5.0
			_:
				if role == HarbourLife.ROLE_SHOPPER:
					item = TownsfolkDrawing.ITEM_BAG if _rng.randf() < 0.5 else TownsfolkDrawing.ITEM_NONE
				position = life.walk_point(life.near_captain_x(_rng), _rng) if settled else _arrival()
				_next()
		queue_redraw()

	func _arrival() -> Vector2:
		var door := life.open_door(_rng) if entry.role == HarbourLife.ROLE_SHOPPER and _rng.randf() < 0.4 else Vector2.INF
		return door if door != Vector2.INF else life.exit_point(_rng)

	func _fisher_spot() -> Vector2:
		var range_ := life.get_x_range()
		var x := lerpf(range_.x, range_.y, 0.12 + float(int(entry.seed) % 20) / 100.0)
		for attempt in 6:
			if not life.near_bench(x, 150.0) and absf(x) > QuayLayout.WALKWAY_CLEAR + 80.0:
				break
			x += 170.0
		return Vector2(x, QuayLayout.EDGE_Y - 62.0)

	## What next (walkers and shoppers): a stroll to somewhere, a pause, or
	## into an open shop and out again.
	func _next() -> void:
		_step += 1
		_rng.seed = int(entry.seed) + _step * 7919
		if entry.role == HarbourLife.ROLE_SHOPPER and _rng.randf() < 0.45:
			var door := life.open_door(_rng)
			if door != Vector2.INF:
				_go(door, INSIDE)
				return
		if _rng.randf() < 0.22:
			var bench := life.bench_seat(_rng)
			if bench != Vector2.INF:
				_go(bench, BENCH)
				return
		_go(life.pause_point(_rng), PAUSE)

	func _go(target: Vector2, then: StringName) -> void:
		state = WALK
		_on_bench = false
		_then = then
		# Out to the walking line, along it, then in to the target.
		_path = PackedVector2Array()
		var line_y := HarbourLife.WALK_Y + _rng.randf_range(-HarbourLife.WALK_SPREAD, HarbourLife.WALK_SPREAD)
		if absf(position.y - line_y) > 30.0:
			_path.append(Vector2(position.x, line_y))
		if absf(target.y - line_y) > 30.0:
			_path.append(Vector2(target.x, line_y))
		_path.append(target)

	func leave() -> void:
		if leaving:
			return
		leaving = true
		if state == INSIDE:
			visible = true
		_go(life.exit_point(_rng), &"gone")

	func _sit() -> void:
		state = SIT
		var seat: Dictionary = life.layout.cafe_seats[int(entry.seat)]
		position = seat.at
		facing = seat.facing

	func advance(delta: float) -> void:
		_time += delta
		match state:
			WALK:
				_walk(delta)
			PAUSE:
				_swing = move_toward(_swing, 0.0, delta * 4.0)
				_wait -= delta
				# Someone stands too close: move on rather than stand in the way.
				if _wait <= 0.0 or (life.captain and life.captain.position.distance_to(position) < 34.0):
					_next()
				queue_redraw()
			INSIDE:
				_wait -= delta
				if _wait <= 0.0:
					visible = true
					item = TownsfolkDrawing.ITEM_BAG if entry.role == HarbourLife.ROLE_SHOPPER else item
					_next()
			LOCK:
				_wait -= delta
				if _wait <= 0.0:
					leave()
			SIT, FISH:
				if fmod(_time, 4.5) < delta:
					queue_redraw()  # a small movement now and then (turning a page, a word)

	func _walk(delta: float) -> void:
		if _path.is_empty():
			_arrive()
			return
		var target := _path[0]
		var to := target - position
		if to.length() < 4.0:
			_path.remove_at(0)
			if _path.is_empty():
				_arrive()
			return
		var direction := to.normalized()
		# Step around the Captain: a sideways push while close and ahead.
		if life.captain:
			var away := position - life.captain.position
			var d := away.length()
			if d < HarbourLife.AVOID_RADIUS and d > 0.1 and direction.dot(-away / d) > -0.2:
				var side := direction.orthogonal()
				if side.dot(away) < 0.0:
					side = -side
				direction = (direction + side * (1.0 - d / HarbourLife.AVOID_RADIUS) * 1.6).normalized()
		var step := minf(_speed * delta, to.length())
		position += direction * step
		facing = facing.lerp(direction, minf(delta * 8.0, 1.0)).normalized()
		_phase = fmod(_phase + step / 46.0 * PI, TAU)
		_swing = sin(_phase)
		queue_redraw()

	func _arrive() -> void:
		match _then:
			&"gone":
				life._forget(self)
			INSIDE:
				state = INSIDE
				visible = false
				_wait = _rng.randf_range(8.0, 22.0)
			SIT:
				_sit()
			BENCH:
				state = PAUSE
				_on_bench = true
				facing = Vector2.DOWN
				_wait = _rng.randf_range(20.0, 45.0)
			FISH:
				state = FISH
				facing = Vector2.DOWN
			_:
				state = PAUSE
				_wait = _rng.randf_range(3.0, 11.0)
				# Look at what one came for: the window, the water.
				facing = Vector2.UP if position.y < 200.0 else Vector2.DOWN
		queue_redraw()

	func is_seated() -> bool:
		return state == SIT

	func _draw() -> void:
		if state == FISH:
			# The nets in a heap beside him, a float or two, a crate.
			var net := Vector2(34, 6)
			draw_circle(net + Vector2(4, 5), 26.0, Color(0.02, 0.04, 0.05, 0.22))
			for k in 6:
				draw_arc(net + Vector2(k % 3 * 6 - 6, k / 3 * 6 - 3), 20.0 - k, 0.3 * k, 0.3 * k + PI * 1.4, 12, Color("#5E6F5A"), 2.0, true)
			draw_circle(net + Vector2(14, -12), 5.0, Color("#D9783A"))
			draw_circle(net + Vector2(-10, 14), 5.0, Color("#D9783A"))
			draw_rect(Rect2(Vector2(-58, -16), Vector2(30, 24)), Color("#7A6048"))
		var turn := facing
		if state in [SIT, FISH]:
			# A small turn of the head and hands now and then.
			turn = facing.rotated(sin(_time * 0.7 + float(int(entry.seed) % 7)) * 0.25)
		TownsfolkDrawing.draw(self, turn, _swing if state == WALK else 0.0, look, state == SIT or _on_bench, item)
