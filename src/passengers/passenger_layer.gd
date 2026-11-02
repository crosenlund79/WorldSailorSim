class_name PassengerLayer
extends Node2D
## The passengers aboard, seen (I028 Tier 2): every person of every booking
## aboard is drawn in the Real Horizon townsfolk style (TownsfolkDrawing) with
## the shared walk (HumanGait), in the deck or the cabin by the hour and the
## weather - on deck by day in fair weather (reading, coffee, watching the
## water, photographs, the animals), below in rough weather and at night
## (resting in the berths the boat offers, Accommodation's places). They walk
## aboard over the side when they board in harbour, and walk off again at
## their harbour. Now and then a small bubble shows what they just said
## (GameSession.passenger_said).
##
## Presentation only: no collision, no stations; it never changes the game.
## Rebuilt from GameSession.get_passengers_aboard() on passages_changed.

const WALK_SPEED := 70.0
const BUBBLE_S := 5.0
const ACTIVITY_REFRESH_S := 4.0
## Local hours below deck (asleep).
const NIGHT_FROM := 22.0
const NIGHT_TO := 7.0

var area: BoatArea
## key "booking:index" -> {"pos", "path", "look", "facing", "phase", "amount", "seated", "item", "leaving", "name", "activity", "pet"}
var people := {}
var _bubbles := {}  # given name -> {"text", "until"}
var _refresh := 0.0
var _font: Font


func setup(boat_area: BoatArea) -> void:
	area = boat_area
	name = "Passengers"
	z_index = 2
	_font = ThemeDB.fallback_font


func _ready() -> void:
	GameSession.passages_changed.connect(_sync)
	GameSession.passenger_said.connect(_on_said)
	_sync()


## Is this area where the passengers are now (deck or cabin)?
static func passengers_below() -> bool:
	var hour := GameSession.get_local_hour()
	var night := hour >= NIGHT_FROM or hour < NIGHT_TO
	return night or GameSession.get_weather_exposure().level >= WeatherModel.HAZARD_DANGEROUS


func _here() -> bool:
	if area == null:
		return false
	return (area.area_id == SessionState.AREA_INTERIOR) == passengers_below()


func _sync() -> void:
	var wanted := {}
	var aboard := GameSession.get_passengers_aboard()
	var slot := 0
	var total := 0
	for entry: Dictionary in aboard:
		total += int(entry.booking.size)
	for entry: Dictionary in aboard:
		var booking: Dictionary = entry.booking
		var traveller: Dictionary = entry.traveller
		var names: Array = traveller.get("names", [traveller.get("given", "")])
		for i in int(booking.size):
			var key := "%s:%d" % [booking.id, i]
			wanted[key] = true
			if not people.has(key):
				people[key] = _new_person(traveller, i, String(names[i] if i < names.size() else names[0]), slot, total, booking)
			slot += 1
	for key: String in people.keys():
		if not wanted.has(key) and not people[key].leaving:
			_leave(key)
	_place_all()
	queue_redraw()


func _new_person(traveller: Dictionary, index: int, given: String, slot: int, total: int, booking: Dictionary) -> Dictionary:
	var person := {"look": TownsfolkDrawing.make_look(HarbourDressing.archetype_for(GameSession.get_location_id()), int(traveller.get("look", 0)) + index * 7919),
		"facing": Vector2.DOWN, "phase": 0.0, "amount": 0.0, "seated": false, "item": TownsfolkDrawing.ITEM_NONE, "leaving": false,
		"name": given, "slot": slot, "total": total, "traveller": traveller, "path": PackedVector2Array(), "pos": Vector2.ZERO}
	var spot := _spot_for(person)
	person.pos = spot
	# Boarding just now, moored, on deck: they walk aboard from the pontoon.
	var just_boarded := GameSession.get_game_time() - float(booking.get("boarded_at", 0.0)) < 1800.0
	if just_boarded and not GameSession.is_underway() and area and area.area_id == SessionState.AREA_EXTERIOR:
		var start := area.get_walkway_return_point()
		person.pos = start
		person.path = PackedVector2Array([start, spot])
		person.wait = 1.2 * slot  # one after another up the gangway
	return person


func _leave(key: String) -> void:
	var person: Dictionary = people[key]
	if not GameSession.is_underway() and area and area.area_id == SessionState.AREA_EXTERIOR and _here_for_leaving():
		person.leaving = true
		person.seated = false
		person.path = PackedVector2Array([person.pos, area.get_walkway_return_point() + Vector2(0, 60)])
	else:
		people.erase(key)


func _here_for_leaving() -> bool:
	return area != null and area.area_id == SessionState.AREA_EXTERIOR


## Where person `slot` of `total` spends this hour, and doing what.
func _spot_for(person: Dictionary) -> Vector2:
	if area == null:
		return Vector2.ZERO
	var slot: int = person.slot
	if area.area_id == SessionState.AREA_INTERIOR:
		var places := _berth_points()
		if not places.is_empty():
			return places[slot % places.size()] + Vector2(0.0, 18.0 * floorf(float(slot) / places.size()))
		return Vector2(-60.0 + slot * 40.0, 0.0)
	var spots := area.get_node_or_null(^"Layout/DeckCompanionSpots") as DeckCompanionSpots
	if spots == null:
		return Vector2(-200.0 + slot * 45.0, 20.0)
	var base := spots.get_spot(0) if slot % 2 == 0 else spots.get_spot(1)
	var offset := Vector2(-30.0 * (slot / 2), 38.0 * (1 if slot % 2 == 0 else -1))
	return spots.nearest_safe(base + offset)


## The guests' sleeping places in the cabin (Accommodation's places not the skipper's).
func _berth_points() -> Array[Vector2]:
	var points: Array[Vector2] = []
	var data := Accommodation.of(GameSession.get_vessel_id())
	for place: Dictionary in data.get("sleeping", []):
		if place.get("for", "") == Accommodation.FOR_SKIPPER:
			continue
		var node := area.find_child(String(place.get("node", "")), true, false) as Node2D
		if node:
			points.append(to_local(node.global_position))
	return points


func _place_all() -> void:
	var hour := GameSession.get_local_hour()
	var night := hour >= NIGHT_FROM or hour < NIGHT_TO
	var pets := GameSession.get_companion_count() > 0
	for key: String in people:
		var person: Dictionary = people[key]
		if person.leaving or not (person.path as PackedVector2Array).is_empty():
			continue
		var traveller: Dictionary = person.traveller
		var spot := _spot_for(person)
		if person.pos.distance_to(spot) > 4.0:
			person.path = PackedVector2Array([person.pos, spot])
			continue
		person.seated = true
		if area.area_id == SessionState.AREA_INTERIOR:
			person.item = TownsfolkDrawing.ITEM_NONE
			person.activity = "sleeping" if night else "resting"
		else:
			var choice := absi(hash("%s|%d" % [key, floori(GameSession.get_game_time() / 7200.0)])) % 4
			if traveller.get("motivation", "") == "photo" or traveller.get("background", "") == "photographer":
				person.activity = "photographing"
				person.seated = false
				person.item = TownsfolkDrawing.ITEM_BAG
			elif pets and traveller.get("pets", "") == "likes" and choice < 2:
				person.activity = "with the animals"
				person.item = TownsfolkDrawing.ITEM_NONE
			else:
				person.activity = ["reading", "coffee", "watching the water", "resting"][choice]
				person.item = [TownsfolkDrawing.ITEM_PAPER, TownsfolkDrawing.ITEM_CUP, TownsfolkDrawing.ITEM_NONE, TownsfolkDrawing.ITEM_NONE][choice]
		person.facing = Vector2(0.0, -signf(person.pos.y)) if absf(person.pos.y) > 2.0 else Vector2.DOWN


func _process(delta: float) -> void:
	if people.is_empty() and _bubbles.is_empty():
		return
	visible = _here() or people.values().any(func(p: Dictionary) -> bool: return p.leaving or not (p.path as PackedVector2Array).is_empty())
	var moving := false
	for key: String in people.keys():
		var person: Dictionary = people[key]
		var path: PackedVector2Array = person.path
		if path.is_empty():
			person.amount = HumanGait.ease_amount(float(person.amount), false, delta)
			continue
		moving = true
		if float(person.get("wait", 0.0)) > 0.0:
			person.wait = float(person.wait) - delta
			continue
		var target := path[path.size() - 1]
		var step := WALK_SPEED * delta
		var to_target: Vector2 = target - person.pos
		if to_target.length() <= step:
			person.pos = target
			person.path = PackedVector2Array()
			if person.leaving:
				people.erase(key)
				continue
		else:
			person.pos += to_target.normalized() * step
			person.facing = to_target.normalized()
			person.seated = false
		person.phase = HumanGait.advance(float(person.phase), step)
		person.amount = HumanGait.ease_amount(float(person.amount), true, delta)
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = ACTIVITY_REFRESH_S
		_place_all()
	var now := Time.get_ticks_msec() / 1000.0
	for given: String in _bubbles.keys():
		if now > float(_bubbles[given].until):
			_bubbles.erase(given)
	if moving or not _bubbles.is_empty():
		queue_redraw()


func _on_said(given: String, text: String) -> void:
	_bubbles[given] = {"text": text, "until": Time.get_ticks_msec() / 1000.0 + BUBBLE_S}
	queue_redraw()


func _draw() -> void:
	for key: String in people:
		var person: Dictionary = people[key]
		draw_set_transform(person.pos)
		TownsfolkDrawing.draw(self, person.facing, HumanGait.swing(float(person.phase), float(person.amount)), person.look, bool(person.seated),
			person.item, float(person.phase), float(person.amount))
		if person.get("activity", "") == "sleeping":
			draw_string(_font, Vector2(14, -18), "z z", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.7))
		if _bubbles.has(String(person.name)):
			_draw_bubble(String(_bubbles[String(person.name)].text))
	draw_set_transform(Vector2.ZERO)


func _draw_bubble(text: String) -> void:
	var shown := text if text.length() <= 46 else text.left(44) + "…"
	var size := _font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	var box := Rect2(Vector2(-size.x * 0.5 - 10.0, -64.0 - size.y), size + Vector2(20.0, 12.0))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.97, 0.96, 0.92, 0.94)
	style.set_corner_radius_all(8)
	draw_style_box(style, box)
	draw_colored_polygon(PackedVector2Array([Vector2(-6, box.end.y - 1), Vector2(6, box.end.y - 1), Vector2(0, box.end.y + 9)]), style.bg_color)
	draw_string(_font, box.position + Vector2(10.0, 6.0 + size.y * 0.78), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#22303A"))


## The people now drawn (tests): [{"name", "activity", "pos", "walking"}].
func get_people() -> Array:
	var list: Array = []
	for key: String in people:
		var p: Dictionary = people[key]
		list.append({"name": p.name, "activity": p.get("activity", ""), "pos": p.pos, "walking": not (p.path as PackedVector2Array).is_empty()})
	return list
