class_name QuayLayout
extends RefCounted
## Where everything stands on a harbour's quay (I026 stage 02, HarbourFront):
## a pure, deterministic layout from the harbour id, so the same harbour
## always has the same quay and tests can read it without a scene.
##
## Coordinates are the quay screen's: x along the waterfront (the walkway from
## the guest pontoon arrives at x = 0), y down the screen. The building fronts
## stand on y = 0 (their facades are drawn upright above it), the promenade
## runs from there to the granite coping at EDGE_Y, and the water and the
## head of the guest pontoon lie below. People, doors, the walkway and
## everything the Captain uses are at true scale, as everywhere around the
## boat: about 1 cm per unit (HarbourDressing.METRE). I027 (the Captain's
## "believable human scale, compressed environmental scale"): the frontages,
## the travel lift's dock and the promenade's depth are compressed, and one
## ordinary house closes each end, so a walk along the shops stays short; each
## business keeps its sign and its own front.
##
## The order along the quay is the harbour's working end to its town end:
## the boatyard (with its travel lift where the yard hauls out), the sail
## loft and the chandlery beside it, the harbour office with the noticeboard
## by the walkway, then the café, the grocery store and the fishmonger's
## stall, and the lane into town (Go Ashore). Only the businesses the harbour
## offers stand there (HarbourFacilities; the trades follow their parent
## exactly as HarbourTrades says); ordinary houses fill the rest. The café,
## the harbour office and the noticeboard are in every harbour.

const BOATYARD := &"boatyard"
const SAIL_LOFT := &"sail_loft"
const CHANDLERY := &"chandlery"
const HARBOUR_OFFICE := &"harbour_office"
const NOTICEBOARD := &"noticeboard"
const CAFE := &"cafe"
const GROCERY := &"grocery"
const FISHMONGER := &"fishmonger"
const LANE := &"lane"
const HOUSE := &"house"
## The businesses with a door (and a counter view), in quay order.
const BUSINESSES: Array[StringName] = [BOATYARD, SAIL_LOFT, CHANDLERY, HARBOUR_OFFICE, CAFE, GROCERY, FISHMONGER]

## The promenade: building fronts at y = 0, the coping's water edge here.
const EDGE_Y := 350.0
## The coping along the water.
const COPING := 32.0
## Half the walkway's width where it comes up from the pontoon.
const WALKWAY_HALF := 48.0
## A business's door: half its width, and how far in front of it its
## interaction stands (on the promenade).
const DOOR_HALF := 55.0
const STATION_Y := 46.0
## Where nobody lingers: in front of a door (this deep) and around the
## walkway's head (this wide).
const DOOR_CLEAR := 110.0
const WALKWAY_CLEAR := 130.0

## Frontages (scene units): [min, max] per kind (compressed in I027: they
## were about half as wide again).
const WIDTHS := {
	BOATYARD: [860.0, 940.0], SAIL_LOFT: [430.0, 470.0], CHANDLERY: [460.0, 520.0], HARBOUR_OFFICE: [440.0, 490.0],
	CAFE: [580.0, 640.0], GROCERY: [460.0, 520.0], FISHMONGER: [380.0, 420.0], HOUSE: [380.0, 460.0], LANE: [250.0, 280.0],
}
## The travel lift's dock beside the boatyard (only where the yard hauls out).
const LIFT_WIDTH := 460.0
## The open walking lane along the whole quay, past every door (I027): no
## table, board, bench, stall or hull stands in it, so the businesses are a
## short, straight walk apart. The shops' own things stay above it, the café's
## terrace below it.
const LANE_Y := 128.0
const LANE_HALF := 24.0
## The café's terrace: its tables' two rows (y), a row apart.
const TERRACE_Y := 185.0
const TERRACE_ROW := 50.0

var port_id: StringName = &""
var archetype: StringName = HarbourDressing.ARCHETYPE_NORDIC
var tier: StringName = HarbourFacilities.TIER_LARGER
var haul_out := false
## Every frontage, left to right: {"id", "x0", "x1", "door" (x), "kind"}.
## Businesses, houses and the lane alike ("kind" is the id for the
## businesses, HOUSE or LANE otherwise).
var fronts: Array[Dictionary] = []
## The noticeboard's place on the promenade (its post's foot).
var noticeboard := Vector2.ZERO
## The fuel berth (I027): a pump at the coping by the walkway's head, in
## every harbour (a card pump, open at any hour).
var fuel_berth := Vector2.ZERO
## The travel lift's dock in the quay edge: x range (empty without one).
var lift := Vector2.ZERO
## The quay's walkable x range.
var left := 0.0
var right := 0.0
## The café's terrace tables (centres) and the seats around them.
var cafe_tables: Array[Vector2] = []
## [{"at", "table", "facing"}]: two chairs per table, facing it.
var cafe_seats: Array[Dictionary] = []


static func build(port_id_: StringName) -> QuayLayout:
	var layout := QuayLayout.new()
	layout._build(port_id_)
	return layout


func _build(port_id_: StringName) -> void:
	port_id = port_id_
	archetype = HarbourDressing.archetype_for(port_id)
	var facilities := HarbourFacilities.for_port(port_id)
	tier = facilities.get_tier()
	haul_out = facilities.has(HarbourFacilities.HAUL_OUT)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("quay:%s" % port_id)
	# Left of the walkway, from it outwards; right of it likewise.
	var west: Array[StringName] = [HARBOUR_OFFICE]
	if facilities.has(HarbourFacilities.CHANDLERY):
		west.append(CHANDLERY)
	if facilities.has(HarbourFacilities.SAILMAKER):
		west.append(SAIL_LOFT)
	if facilities.has(HarbourFacilities.BOATYARD):
		west.append(BOATYARD)
	west.append(HOUSE)
	var east: Array[StringName] = [CAFE]
	if facilities.has(HarbourFacilities.GROCERY):
		east.append(GROCERY)
	if facilities.has(HarbourFacilities.FISHMONGER):
		east.append(FISHMONGER)
	if facilities.has(HarbourFacilities.GO_ASHORE):
		east.append(LANE)
	east.append(HOUSE)
	# The walkway arrives between the office and the café: the noticeboard
	# stands there, by the walkway's head.
	var x := -WALKWAY_HALF - 70.0
	for id in west:
		var w := _width(id, rng)
		if id == BOATYARD and haul_out:
			lift = Vector2(x - w - LIFT_WIDTH, x - w)
			_add(id, x - w, x, rng)
			x -= w + LIFT_WIDTH + rng.randf_range(20.0, 40.0)
			continue
		_add(id, x - w, x, rng)
		x -= w + (rng.randf_range(10.0, 40.0) if rng.randf() < 0.5 else 0.0)
	left = x - 40.0
	x = WALKWAY_HALF + 70.0
	for id in east:
		var w := _width(id, rng)
		_add(id, x, x + w, rng)
		x += w + (rng.randf_range(10.0, 40.0) if rng.randf() < 0.5 and id != LANE else 0.0)
	right = x + 40.0
	fronts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.x0) < float(b.x0))
	# By the walkway's head, on the water side of the walking lane.
	noticeboard = Vector2(-WALKWAY_HALF - 150.0, LANE_Y + LANE_HALF + 34.0)
	fuel_berth = Vector2(WALKWAY_HALF + 232.0, EDGE_Y - 24.0)
	var cafe := get_front(CAFE)
	if not cafe.is_empty():
		var n := 3
		var span := float(cafe.x1) - float(cafe.x0)
		for i in n:
			var tx := float(cafe.x0) + span * (i + 0.5) / n
			# Clear of the café's own door.
			if absf(tx - float(cafe.door)) < DOOR_HALF + 60.0:
				tx += (DOOR_HALF + 70.0) * signf(tx - float(cafe.door) + 0.01)
			var table := Vector2(tx, TERRACE_Y + (i % 2) * TERRACE_ROW)
			cafe_tables.append(table)
			for side: float in [-1.0, 1.0]:
				cafe_seats.append({"at": table + Vector2(side * 52.0, 0.0), "table": table, "facing": Vector2(-side, 0.0)})


func _width(id: StringName, rng: RandomNumberGenerator) -> float:
	var range_: Array = WIDTHS.get(id, WIDTHS[HOUSE])
	return roundf(rng.randf_range(range_[0], range_[1]))


func _add(id: StringName, x0: float, x1: float, rng: RandomNumberGenerator) -> void:
	var door := (x0 + x1) / 2.0
	if id in [CHANDLERY, GROCERY, CAFE, HARBOUR_OFFICE, HOUSE]:
		# The door off-centre, the shop window beside it.
		door = lerpf(x0, x1, 0.3 if rng.randf() < 0.5 else 0.7)
	elif id == BOATYARD:
		door = lerpf(x0, x1, 0.82)  # the yard office's door beside the big shed doors
	fronts.append({"id": id, "kind": id, "x0": x0, "x1": x1, "door": door, "seed": rng.randi()})


## The frontage of `id` ({} when this harbour has none).
func get_front(id: StringName) -> Dictionary:
	for front in fronts:
		if front.id == id:
			return front
	return {}


func has_business(id: StringName) -> bool:
	return id == NOTICEBOARD or not get_front(id).is_empty()


## The businesses this quay has (with a door), in quay order.
func get_businesses() -> Array[StringName]:
	var out: Array[StringName] = []
	for front in fronts:
		if front.id in BUSINESSES:
			out.append(front.id)
	return out


## Where the Captain stands to use a door (on the promenade before it).
func door_station(id: StringName) -> Vector2:
	var front := get_front(id)
	return Vector2(float(front.door), STATION_Y) if not front.is_empty() else Vector2.INF


## Where the Captain arrives on the quay from the walkway (and leaves).
func arrival_point() -> Vector2:
	return Vector2(0.0, EDGE_Y - 60.0)


## True when a figure standing at `p` would be in someone's way: in front of
## a door, or at the walkway's head.
func is_in_the_way(p: Vector2) -> bool:
	if absf(p.x) < WALKWAY_CLEAR and p.y > EDGE_Y - 130.0:
		return true
	for front in fronts:
		if front.kind in BUSINESSES or front.kind == LANE:
			var half := DOOR_HALF + 25.0 if front.kind != LANE else (float(front.x1) - float(front.x0)) / 2.0
			var door := float(front.door)
			if absf(p.x - door) < half and p.y < DOOR_CLEAR:
				return true
	return false
