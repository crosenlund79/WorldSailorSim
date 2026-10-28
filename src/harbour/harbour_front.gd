class_name HarbourFront
extends Node2D
## The quay (I026 stage 02, living harbours): the walkable waterfront at the
## head of the guest pontoon, where every business has its own home.
##
## Reached from the deck by the pontoon's walkway ("To the quay",
## BoatArea), left by walking back down it (or E at its head). It is a
## screen like the chart, not a boat area: GameSession still has the Captain
## on deck, on the pontoon by the walkway, so a save made here loads aboard
## by the walkway and the save format is unchanged. Time passes as always.
##
## Built from the harbour id (QuayLayout): the water and the pontoon's head
## at the bottom, the promenade in the middle, the storefronts along the top
## (StorefrontDrawing) - only the businesses the harbour has, in its regional
## style - and its people (HarbourLife). The camera follows the Captain along
## the quay at true scale.
##
## Like BoatArea it is presentation and routing only: each door is an
## Interactable (the focus glow around the storefront, a prompt, E), and
## using one emits `place_requested`; App opens the business's existing menu
## in its shop-counter frame, checks the hours (BusinessHours) and offers to
## wait for opening time. The café's seat is the one thing handled here: the
## Captain sits at a terrace table with a mug (nothing in the game state
## changes) and stands up with E or a movement key.

## A place on the quay was used: a business id (QuayLayout), HATCH,
## QuayLayout.NOTICEBOARD, QuayLayout.LANE or TRAVEL_LIFT.
signal place_requested(place: StringName)
## The Captain walks back down to the pontoon.
signal leave_requested
signal message_requested(text: String)
signal interaction_prompt_changed(prompt: String)

const HATCH := &"hatch"
const TRAVEL_LIFT := &"travel_lift"
const WALKWAY := &"walkway"
## The camera: the screen's zoom (true scale, like the decks) and the height
## it keeps (the facades above, the water's edge below).
const ZOOM := 1.05
const CAMERA_Y := 140.0
const CAMERA_RATE := 4.0
## How often (real seconds) the doors, prompts and light follow the clock.
const REFRESH_SECONDS := 1.0

var layout: QuayLayout
var port_id: StringName = &""
var life: HarbourLife
var ground: QuayDrawing
## Storefront drawings by front id (businesses; houses and the lane too).
var storefronts := {}
## Stations by place id.
var stations := {}
var companions: Array[QuayCompanion] = []
## The café seat the Captain sits on ({} while standing).
var seat: Dictionary = {}
var seat_index := -1

var _leaving := false
var _refresh := 0.0
var _modulate: CanvasModulate
var _lights: Array[Dictionary] = []
var _darkness := 0.0
var _colour := Color.WHITE
var _initialised := false

@onready var player: Player = $Player
@onready var camera: Camera2D = $Camera2D


func _ready() -> void:
	port_id = GameSession.get_location_id()
	layout = QuayLayout.build(port_id)
	_build_ground()
	_build_storefronts()
	_build_walls()
	_build_stations()
	life = HarbourLife.new()
	life.name = "HarbourLife"
	add_child(life)
	move_child(life, player.get_index())
	life.benches = ground.get_bench_positions()
	life.setup(layout, player)
	_build_companions()
	_build_lighting()
	player.position = layout.arrival_point()
	player.set_facing(Vector2.UP)
	player.focus_changed.connect(func(station: Interactable) -> void: interaction_prompt_changed.emit(station.prompt if station else ""))
	camera.zoom = Vector2.ONE * ZOOM
	camera.position = Vector2(_camera_x(player.position.x), CAMERA_Y)
	camera.reset_smoothing()
	refresh()
	_update_light(0.0)
	SessionLog.write("quay", {"port": String(port_id), "businesses": layout.get_businesses().map(func(b: StringName) -> String: return String(b)),
		"people": life.get_person_count()})


func get_layout() -> QuayLayout:
	return layout


func get_station(place: StringName) -> Interactable:
	return stations.get(place) as Interactable


func get_storefront(id: StringName) -> StorefrontDrawing:
	return storefronts.get(id) as StorefrontDrawing


# --- Building ----------------------------------------------------------------------

func _build_ground() -> void:
	ground = QuayDrawing.new()
	ground.name = "Ground"
	add_child(ground)
	move_child(ground, 0)
	ground.setup(layout)


func _build_storefronts() -> void:
	var holder := Node2D.new()
	holder.name = "Storefronts"
	add_child(holder)
	move_child(holder, 1)
	for front in layout.fronts:
		var drawing := StorefrontDrawing.new()
		drawing.name = "Front_%s_%d" % [front.id, roundi(float(front.x0))]
		holder.add_child(drawing)
		drawing.setup(front, layout)
		if front.id != QuayLayout.HOUSE:
			storefronts[front.id] = drawing


## The quay's edges (the house fronts, the water with the walkway's gap,
## the ends) and the solid things on the promenade. The Captain only.
func _build_walls() -> void:
	var body := StaticBody2D.new()
	body.name = "Walls"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var left := layout.left
	var right := layout.right
	var edge := QuayLayout.EDGE_Y - 6.0
	var down := QuayLayout.EDGE_Y + 70.0
	_segment(body, Vector2(left, 2.0), Vector2(right, 2.0))
	_segment(body, Vector2(left, 2.0), Vector2(left, edge))
	_segment(body, Vector2(right, 2.0), Vector2(right, edge))
	_segment(body, Vector2(left, edge), Vector2(-QuayLayout.WALKWAY_HALF + 6.0, edge))
	_segment(body, Vector2(QuayLayout.WALKWAY_HALF - 6.0, edge), Vector2(right, edge))
	_segment(body, Vector2(-QuayLayout.WALKWAY_HALF + 6.0, edge), Vector2(-QuayLayout.WALKWAY_HALF + 6.0, down))
	_segment(body, Vector2(QuayLayout.WALKWAY_HALF - 6.0, edge), Vector2(QuayLayout.WALKWAY_HALF - 6.0, down))
	_segment(body, Vector2(-QuayLayout.WALKWAY_HALF, down), Vector2(QuayLayout.WALKWAY_HALF, down))
	var dock := ground.get_lift_dock()
	if dock.has_area():
		_box(body, dock.grow(6.0))
	for table in layout.cafe_tables:
		_circle(body, table, 30.0)
	for lamp in ground.get_lamp_positions():
		_circle(body, lamp + Vector2(0, 0), 10.0)
	for bollard in ground.get_bollard_positions():
		_circle(body, bollard, 13.0)
	for bench in ground.get_bench_positions():
		_box(body, Rect2(bench + Vector2(-80, -20), Vector2(160, 40)))
	_box(body, Rect2(layout.noticeboard + Vector2(-70, -12), Vector2(140, 16)))
	for front in layout.fronts:
		var x0 := float(front.x0)
		var w := float(front.x1) - x0
		match front.kind:
			QuayLayout.BOATYARD:
				var length := minf(w * 0.55, 760.0)
				_box(body, Rect2(x0 + w * 0.36 - length / 2.0, 40.0, length, 270.0))  # the hull on its stands
				_box(body, Rect2(x0 + w * 0.06, 50.0, 160.0, 44.0))  # the workbench
				_box(body, Rect2(x0 + w * 0.7 - 15.0, 55.0, 64.0, 30.0))  # the drums
			QuayLayout.SAIL_LOFT:
				_box(body, Rect2(x0 + w * 0.2 - 70.0, 65.0, 310.0, 40.0))
			QuayLayout.FISHMONGER:
				_box(body, Rect2(x0 + 30.0, 30.0, w - 210.0, 70.0))


func _segment(body: StaticBody2D, a: Vector2, b: Vector2) -> void:
	var shape := SegmentShape2D.new()
	shape.a = a
	shape.b = b
	var owner_shape := CollisionShape2D.new()
	owner_shape.shape = shape
	body.add_child(owner_shape)


func _box(body: StaticBody2D, rect: Rect2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var owner_shape := CollisionShape2D.new()
	owner_shape.shape = shape
	owner_shape.position = rect.get_center()
	body.add_child(owner_shape)


func _circle(body: StaticBody2D, at: Vector2, radius: float) -> void:
	var shape := CircleShape2D.new()
	shape.radius = radius
	var owner_shape := CollisionShape2D.new()
	owner_shape.shape = shape
	owner_shape.position = at
	body.add_child(owner_shape)


func _build_stations() -> void:
	var holder := Node2D.new()
	holder.name = "Stations"
	add_child(holder)
	for business in layout.get_businesses():
		var station := _add_station(holder, business, layout.door_station(business), Vector2(160, 76))
		var drawing := get_storefront(business)
		if drawing:
			station.set_highlight_outline_global.call_deferred(drawing.get_highlight_outline())
	var office := get_storefront(QuayLayout.HARBOUR_OFFICE)
	if office:
		var hatch := office.get_hatch_rect()
		var at := office.to_global(Vector2(hatch.get_center().x, 0.0)) + Vector2(0.0, QuayLayout.STATION_Y)
		var station := _add_station(holder, HATCH, at, Vector2(110, 70))
		station.prompt = "Ring at the after-hours hatch"
		var outline := PackedVector2Array()
		for p in HighlightResolver.rounded_rect(hatch.grow(10.0), 6.0):
			outline.append(office.to_global(p))
		station.set_highlight_outline_global.call_deferred(outline)
	var board := _add_station(holder, QuayLayout.NOTICEBOARD, layout.noticeboard + Vector2(0.0, 34.0), Vector2(150, 60))
	board.prompt = "Read the noticeboard"
	board.set_highlight_outline_global.call_deferred(ground.get_noticeboard_outline())
	var lane := layout.get_front(QuayLayout.LANE)
	if not lane.is_empty():
		var station := _add_station(holder, QuayLayout.LANE, Vector2(float(lane.door), 40.0), Vector2(float(lane.x1) - float(lane.x0) - 40.0, 70))
		station.prompt = "Into town (Go ashore)"
		var drawing := get_storefront(QuayLayout.LANE)
		if drawing:
			station.set_highlight_outline_global.call_deferred(drawing.get_highlight_outline())
	if layout.lift != Vector2.ZERO:
		var dock := ground.get_lift_dock()
		var station := _add_station(holder, TRAVEL_LIFT, Vector2(dock.get_center().x, 40.0), Vector2(dock.size.x + 60.0, 60))
		station.prompt = "Ask about a haul-out"
		station.set_highlight_outline_global.call_deferred(ground.get_lift_outline())
	var walkway := _add_station(holder, WALKWAY, Vector2(0.0, QuayLayout.EDGE_Y - 34.0), Vector2(120, 60))
	walkway.prompt = "Back to the boat"
	walkway.focus_priority = -1
	for station: Interactable in stations.values():
		station.interacted.connect(_on_interacted)


func _add_station(holder: Node, place: StringName, at: Vector2, size: Vector2) -> Interactable:
	var station := Interactable.new()
	station.name = "Station_%s" % place
	station.interaction_id = place
	station.highlight_target = ^""
	station.position = at
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	station.add_child(shape)
	holder.add_child(station)
	stations[place] = station
	return station


func _build_companions() -> void:
	var holder := Node2D.new()
	holder.name = "Companions"
	add_child(holder)
	move_child(holder, player.get_index())
	var slot := 0
	for companion in GameSession.get_companions_ashore():
		var node := QuayCompanion.new()
		holder.add_child(node)
		node.setup(companion, player, slot)
		companions.append(node)
		slot += 1


func get_companion_nodes() -> Array[QuayCompanion]:
	return companions


# --- Light of the hour ---------------------------------------------------------------

func _build_lighting() -> void:
	_modulate = CanvasModulate.new()
	_modulate.name = "Ambient"
	add_child(_modulate)
	for lamp in ground.get_lamp_positions():
		_add_light(lamp + Vector2(0, -24), BoatLighting.QUAY_LAMP, 2.2, 0.9, &"night")
	for business in layout.get_businesses():
		var door := layout.door_station(business)
		_add_light(Vector2(door.x, 20.0), BoatLighting.LAMP_WARM, 1.6, 0.7, business)
	var lane := layout.get_front(QuayLayout.LANE)
	if not lane.is_empty():
		_add_light(Vector2(float(lane.x0) + (float(lane.x1) - float(lane.x0)) * 0.82, -200.0), BoatLighting.QUAY_LAMP, 1.4, 0.7, &"night")


func _add_light(at: Vector2, colour: Color, size: float, energy: float, when: StringName) -> void:
	var light := PointLight2D.new()
	light.texture = BoatLighting.light_texture()
	light.texture_scale = size
	light.color = colour
	light.energy = 0.0
	light.position = at
	light.blend_mode = Light2D.BLEND_MODE_ADD
	add_child(light)
	_lights.append({"light": light, "energy": energy, "when": when})


## 0 in full daylight .. 1 at night.
func get_darkness() -> float:
	return _darkness


func _update_light(delta: float) -> void:
	if not GameSession.is_active():
		return
	var now := GameSession.get_game_time()
	var geo := GameSession.get_vessel_position()
	var overcast := BoatLighting.overcast_of(Simulation.get_weather_at_vessel())
	var elevation := Daylight.sun_elevation(geo, now)
	var target := Daylight.outside_colour(elevation, overcast)
	var dark := clampf(1.0 - Daylight.daylight(elevation) * (1.0 - overcast * 0.5), 0.0, 1.0)
	var t := 1.0 if not _initialised else 1.0 - exp(-2.5 * delta)
	_initialised = true
	_colour = _colour.lerp(target, t)
	_darkness = lerpf(_darkness, dark, t)
	_modulate.color = _colour
	var compensation := Color(1.0 / maxf(_colour.r, 0.3), 1.0 / maxf(_colour.g, 0.3), 1.0 / maxf(_colour.b, 0.3))
	Interactable.light_compensation = compensation
	for drawing in get_node(^"Storefronts").get_children():
		(drawing as StorefrontDrawing).get_lights_node().self_modulate = compensation
	for entry in _lights:
		var light := entry.light as PointLight2D
		var strength := smoothstep(0.45, 0.85, _darkness)
		if entry.when != &"night":
			strength *= 1.0 if BusinessHours.is_open(entry.when, port_id, now) else 0.0
		light.energy = float(entry.energy) * strength
		light.visible = light.energy > 0.01


# --- Following the clock ----------------------------------------------------------------

## The doors (open or shut, lit or dark, the hours plate) and the prompts
## for the hour now.
func refresh() -> void:
	if not GameSession.is_active():
		return
	var now := GameSession.get_game_time()
	var local := BusinessHours.local_hours(port_id, now)
	for drawing in get_node(^"Storefronts").get_children():
		var front := drawing as StorefrontDrawing
		var kind := front.get_kind()
		var plate := ""
		if kind in QuayLayout.BUSINESSES:
			var span := BusinessHours.hours(kind, port_id)
			plate = "%s–%s" % [BusinessHours.format_hour(span.x), BusinessHours.format_hour(span.y)]
		# The homes (houses, and the flats above the shops) light their lamps
		# from late afternoon until bedtime.
		var lamps := local >= 15.5 and local < 23.0 + float(int(front.front.seed) % 3) * 0.5
		if kind in QuayLayout.BUSINESSES:
			front.set_state(BusinessHours.is_open(kind, port_id, now), _darkness, plate, lamps)
		else:
			front.set_state(false, _darkness, "", lamps)
	for place: StringName in stations:
		var station := stations[place] as Interactable
		if place in QuayLayout.BUSINESSES:
			station.prompt = prompt_for(place)
	var focused := player.get_focused_interactable()
	if focused:
		interaction_prompt_changed.emit(focused.prompt)
	# A companion called back aboard leaves the quay.
	for node in companions.duplicate():
		if not GameSession.is_companion_ashore(node.companion.id):
			companions.erase(node)
			node.queue_free()


## A door's prompt: what it is and whether it is open ("Chandlery · open
## until 17:00"; "Chandlery · closed · opens 09:00 (in 2 h 40 min)").
func prompt_for(business: StringName) -> String:
	return "%s · %s" % [business_name(business), BusinessHours.status_text(business, port_id, GameSession.get_game_time())]


## A business's name, as on its sign.
static func business_name(business: StringName) -> String:
	match business:
		QuayLayout.BOATYARD:
			return Loc.t("Boatyard")
		QuayLayout.SAIL_LOFT:
			return Loc.t("Sail Loft")
		QuayLayout.CHANDLERY:
			return Loc.t("Chandlery")
		QuayLayout.HARBOUR_OFFICE:
			return Loc.t("Harbour Office")
		QuayLayout.CAFE:
			return Loc.t("Café")
		QuayLayout.GROCERY:
			return Loc.t("Groceries")
		QuayLayout.FISHMONGER:
			return Loc.t("Fishmonger")
		QuayLayout.NOTICEBOARD:
			return Loc.t("Noticeboard")
	return String(business)


func _process(delta: float) -> void:
	_update_light(delta)
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = REFRESH_SECONDS
		refresh()
	if not _leaving:
		camera.position = Vector2(lerpf(camera.position.x, _camera_x(player.position.x), 1.0 - exp(-CAMERA_RATE * delta)), CAMERA_Y)
	# Walking back down the walkway returns to the boat.
	if not _leaving and seat.is_empty() and player.position.y > QuayLayout.EDGE_Y + 12.0 and absf(player.position.x) < QuayLayout.WALKWAY_HALF:
		leave()


func _camera_x(x: float) -> float:
	var half := get_viewport_rect().size.x / 2.0 / ZOOM
	var lo := layout.left + half - 60.0
	var hi := layout.right - half + 60.0
	return clampf(x, lo, hi) if lo < hi else (layout.left + layout.right) / 2.0


func leave() -> void:
	if _leaving:
		return
	if not seat.is_empty():
		stand_up()
	begin_exit()
	leave_requested.emit()


## Stops play here while the screen changes (SceneRouter).
func begin_exit() -> void:
	_leaving = true
	player.set_input_enabled(false)


func is_leaving() -> bool:
	return _leaving


func _on_interacted(station: Interactable, _actor: Node) -> void:
	if _leaving:
		return
	if station.interaction_id == WALKWAY:
		leave()
		return
	place_requested.emit(station.interaction_id)


# --- The café table ----------------------------------------------------------------

## The free terrace seat nearest the café's door, or -1.
func free_seat() -> int:
	var taken := {}
	for person in life.get_people():
		var entry: Dictionary = person.entry
		if entry.has("seat"):
			taken[int(entry.seat)] = true
	var cafe := layout.get_front(QuayLayout.CAFE)
	var door := Vector2(float(cafe.get("door", 0.0)), 0.0)
	var best := -1
	var best_d := INF
	for i in layout.cafe_seats.size():
		var at: Vector2 = layout.cafe_seats[i].at
		if taken.has(i):
			continue
		if at.distance_to(door) < best_d:
			best_d = at.distance_to(door)
			best = i
	return best


## The Captain sits down at a terrace table with a café mug (after ordering):
## time passes as usual; E or a movement key stands up again. Companions
## ashore settle by the table. Returns false when every seat is taken.
func sit_at_cafe() -> bool:
	var index := free_seat()
	if index < 0:
		return false
	seat_index = index
	seat = layout.cafe_seats[index]
	life.reserved_seats[index] = true
	player.position = seat.at
	player.velocity = Vector2.ZERO
	player.set_facing(seat.facing)
	player.set_input_enabled(false)
	player.cafe_mug = true
	for node in companions:
		node.resting_at = seat
	interaction_prompt_changed.emit(Loc.t("Enjoy your coffee  ·  E or a movement key to stand up"))
	SessionLog.write("cafe_seat", {"port": String(port_id), "seat": index})
	return true


func is_seated() -> bool:
	return not seat.is_empty()


func stand_up() -> void:
	if seat.is_empty():
		return
	life.reserved_seats.erase(seat_index)
	player.position = (seat.at as Vector2) + Vector2(0.0, 52.0)  # out from the table, onto the promenade
	player.cafe_mug = false
	seat = {}
	seat_index = -1
	for node in companions:
		node.resting_at = {}
	if not _leaving:
		player.set_input_enabled(true)
	interaction_prompt_changed.emit("")
	message_requested.emit(Loc.t("You finish your coffee and leave the cup on the table. Lovely."))


func _unhandled_input(event: InputEvent) -> void:
	if seat.is_empty() or _leaving or event.is_echo() or not event.is_pressed():
		return
	for action in [&"interact", &"move_left", &"move_right", &"move_up", &"move_down"]:
		if event.is_action_pressed(action):
			get_viewport().set_input_as_handled()
			stand_up()
			return
