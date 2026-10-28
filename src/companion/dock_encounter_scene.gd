class_name DockEncounterScene
extends Node
## The animal on the dock, on the deck view of a moored boat (I025, A Little
## More Room Aboard). The state is GameSession's (DockEncounters, saved with
## the game); this node only shows it: a small open cardboard box on the
## pontoon, a little way from the gangplank and the services, with a Ragdoll
## sitting in it, a Pug beside it or a conure perched on its rim (a stray
## ShipCompanion, the same art and clips as a companion's).
##
## A few kind gestures (E: a hello, a treat from the Captain's pocket, a
## little play - or simply sitting nearby for a while) and it follows the
## Captain: the cat walks, the Pug trots, the conure flies short hops. At the
## companionway App asks whether to welcome it aboard (AdoptionDialog). Not
## now: it goes back to its box, a little girl comes along the pontoon, it
## goes to her (the cat purring, the Pug wagging, the conure onto her
## shoulder), she picks up the box and they leave together. No words, no
## penalty; the encounter is over (GameSession.decline_dock_animal()).
##
## Built by BoatArea on decks with a shore (ShoreAccess). Its nodes are the
## BoatArea's children (the stray must be, for its walks down the gangplank);
## they go when the encounter does.

## How far from the gangplank the box stands (between the service slots at
## ±215 and ±430, clear of the companions' places on the pontoon).
const BOX_OFFSET := 300.0
## How close it keeps to the Captain while following.
const FOLLOW_GAP := 38.0
const FOLLOW_START := 70.0
## Seconds of quiet nearby that count as a kind gesture.
const WAIT_SECONDS := 14.0
const WAIT_RADIUS := 90.0
const GESTURE_COOLDOWN := 2.2
## Faster than their calm walk while following (the Pug trots).
const PACE := {CompanionState.KIND_CAT: 2.2, CompanionState.KIND_DOG: 3.2, CompanionState.KIND_PARROT: 1.0}

signal farewell_finished

var area: BoatArea
var shore: ShoreAccess
var animal: ShipCompanion
var girl: DockGirl
var kind: StringName = &""
var _box_back: DockBox
var _box_front: DockBox
var _box_at := Vector2.ZERO
var _side := 1.0
var _cooldown := 0.0
var _waited := 0.0
var _waited_used := false
var _retarget := 0.0
var _following := false
var _farewell := false


func setup(boat_area: BoatArea, shore_access: ShoreAccess) -> void:
	area = boat_area
	shore = shore_access
	GameSession.dock_encounter_changed.connect(refresh)
	GameSession.state_replaced.connect(refresh)
	refresh()


## True while the animal follows the Captain (the companionway asks).
func is_following() -> bool:
	return _following and not _farewell and animal != null


## True while the girl's moment plays.
func is_farewell() -> bool:
	return _farewell


func get_box_position() -> Vector2:
	return _box_at


func refresh() -> void:
	if _farewell:
		return
	var current := GameSession.get_dock_encounter()
	if current.is_empty() or shore == null or not shore.is_valid() or not shore.is_active():
		_clear()
		return
	var built := false
	if animal == null or kind != StringName(current.kind):
		_clear()
		_build(StringName(current.kind), String(current.port))
		built = true
	var following: bool = current.state == DockEncounters.STATE_FOLLOWING
	if following and not _following:
		_start_following(built)
	_following = following
	_update_prompt(int(current.trust))


func _build(animal_kind: StringName, port: String) -> void:
	kind = animal_kind
	var strip := shore.get_shore_rect()
	# Downstream of the gangplank, away from the harbour's name painted on
	# the pontoon on the other side (BoatArea), near the pontoon's edge.
	_side = 1.0
	var x := shore.get_plank_x() + BOX_OFFSET * _side
	if x > strip.end.x - 40.0:
		_side = -1.0
		x = shore.get_plank_x() + BOX_OFFSET * _side
	_box_at = Vector2(clampf(x, strip.position.x + 40.0, strip.end.x - 40.0), strip.position.y + minf(30.0, strip.size.y * 0.4))
	_box_back = DockBox.new()
	_box_back.name = "DockBoxBack"
	_box_back.part = DockBox.Part.BACK
	_box_back.position = _box_at
	_box_back.z_index = 4
	area.add_child(_box_back)
	animal = ShipCompanion.new()
	animal.name = "DockAnimal"
	animal.stray = true
	animal.kind = kind
	animal.on_deck = true
	animal.deck_spots = area.get_node_or_null(^"Layout/DeckCompanionSpots") as DeckCompanionSpots
	animal.position = _home()
	area.add_child(animal)
	animal.facing = -_side  # towards the boat
	if animal.has_clip(CompanionVisualSet.POSE_SIT):
		animal.set_pose(CompanionVisualSet.POSE_SIT, 30.0)
	animal.interactable.interacted.connect(func(_i: Interactable, _actor: Node) -> void: befriend())
	_box_front = DockBox.new()
	_box_front.name = "DockBoxFront"
	_box_front.part = DockBox.Part.FRONT
	_box_front.position = _box_at
	_box_front.z_index = 5
	area.add_child(_box_front)
	SessionLog.write("dock_animal_shown", {"kind": String(kind), "port": port})


## Where the animal waits: in the box (the cat), beside it (the Pug), on its
## front rim (the conure).
func _home() -> Vector2:
	match kind:
		CompanionState.KIND_DOG:
			return _box_at + Vector2((DockBox.HALF_WIDTH + 14.0) * -_side, 3.0)
		CompanionState.KIND_PARROT:
			return _box_at + DockBox.RIM
	return _box_at + Vector2(0.0, -DockBox.WALL * 0.45)


func _clear() -> void:
	for node: Node in [_box_back, _box_front, animal, girl]:
		if is_instance_valid(node):
			node.queue_free()
	_box_back = null
	_box_front = null
	animal = null
	girl = null
	kind = &""
	_following = false
	_waited = 0.0


func _update_prompt(trust: int) -> void:
	if animal == null or animal.interactable == null:
		return
	animal.interactable.prompt = CompanionRemarks.befriend_prompt(kind, trust)
	animal.interactable.enabled = trust < DockEncounters.TRUST_NEEDED and not _farewell


## A kind gesture (E on the animal). Returns the line said, or "".
func befriend() -> String:
	if animal == null or _farewell or _cooldown > 0.0 or is_following():
		return ""
	var result := GameSession.befriend_dock_animal()
	if result.is_empty():
		return ""
	return _answer(int(result.step), CompanionRemarks.befriend_line(kind, int(result.step)))


func _answer(step: int, line: String) -> String:
	_cooldown = GESTURE_COOLDOWN
	animal.pet()
	if not animal.respond(CompanionRemarks.befriend_clip(kind, step)):
		animal.respond(CompanionVisualSet.POSE_ALERT)
	area.message_requested.emit(line)
	return line


## It follows from now on; `near_captain`: the deck was just built (back
## from the chart, say) and it is already with the Captain.
func _start_following(near_captain: bool) -> void:
	if animal == null:
		return
	animal.pace = float(PACE.get(kind, 1.0))
	_retarget = 0.0
	if near_captain and area.player:
		animal.position = _safe(area.player.position + Vector2(-FOLLOW_GAP, 10.0))


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if animal == null or _farewell or area == null or area.player == null:
		return
	var captain := area.player.position
	if _following:
		_retarget -= delta
		var gap := animal.position.distance_to(captain)
		if _retarget <= 0.0 and gap > FOLLOW_START:
			_retarget = 0.45
			var away := (animal.position - captain).normalized()
			var target := _safe(captain + away * FOLLOW_GAP)
			if not animal.is_walking() or animal.position.distance_to(target) > 30.0:
				animal.walk_to(target)
		return
	# Waiting quietly nearby also counts, once.
	if not _waited_used and captain.distance_to(animal.position) < WAIT_RADIUS and area.player.velocity.length() < 4.0:
		_waited += delta
		if _waited >= WAIT_SECONDS and _cooldown <= 0.0:
			_waited_used = true
			var result := GameSession.befriend_dock_animal()
			if not result.is_empty():
				var line := CompanionRemarks.waited_line(kind)
				if bool(result.trusting):
					line += " " + Loc.t("It looks as if it would like to come with you.")
				_answer(int(result.step), line)
	else:
		_waited = maxf(_waited - delta * 2.0, 0.0)


## A point it can stand on near `p`: on the pontoon's strip, or a safe place
## aboard.
func _safe(p: Vector2) -> Vector2:
	if shore and shore.is_off_the_boat(p):
		var strip := shore.get_shore_rect().grow(-14.0)
		return Vector2(clampf(p.x, strip.position.x, strip.end.x), clampf(p.y, strip.position.y, strip.end.y))
	if animal and animal.deck_spots:
		return animal.deck_spots.nearest_safe(p, false)
	return p


# --- Not now: the little girl ---------------------------------------------------

## The Captain said not now: the encounter ends (GameSession) and the girl's
## moment plays here.
func decline() -> void:
	if animal == null or _farewell:
		GameSession.decline_dock_animal()
		return
	_farewell = true
	_update_prompt(DockEncounters.TRUST_NEEDED)
	GameSession.decline_dock_animal()
	_play_farewell()


func _play_farewell() -> void:
	animal.pace = float(PACE.get(kind, 1.0))
	# Back to its box.
	animal.walk_to(_home())
	await _until(func() -> bool: return not animal.is_walking(), 20.0)
	if not is_inside_tree():
		return
	animal.facing = _side
	var strip := shore.get_shore_rect()
	var edge := Vector2(strip.end.x - 6.0 if _side > 0.0 else strip.position.x + 6.0, _box_at.y + 6.0)
	girl = DockGirl.new()
	girl.name = "DockGirl"
	girl.position = edge
	girl.modulate.a = 0.0
	area.add_child(girl)
	create_tween().tween_property(girl, "modulate:a", 1.0, 0.6)
	var stop := _box_at + Vector2((DockBox.HALF_WIDTH + 26.0) * _side, 8.0)
	girl.walk_to(stop)
	await _until(func() -> bool: return not girl.is_walking(), 20.0)
	if not is_inside_tree():
		return
	girl.face(Vector2(-_side, 0.0))
	girl.wave(1.4)
	await _seconds(0.5)
	# It goes to her: the cat purring, the Pug wagging, the conure to her shoulder.
	match kind:
		CompanionState.KIND_PARROT:
			animal.walk_to(girl.get_shoulder())
		_:
			animal.walk_to(girl.position + Vector2(-_side * 20.0, 4.0))
	await _until(func() -> bool: return not animal.is_walking(), 12.0)
	if not is_inside_tree():
		return
	if kind != CompanionState.KIND_PARROT:
		animal.facing = _side
	animal.pet()
	animal.respond(CompanionVisualSet.POSE_TAIL_WAG if kind == CompanionState.KIND_DOG else CompanionVisualSet.POSE_PET)
	await _seconds(1.6)
	if not is_inside_tree():
		return
	# She picks up the box, and they leave together.
	girl.face(Vector2(-_side, 0.0))
	_box_back.visible = false
	_box_front.visible = false
	girl.carrying_box = true
	await _seconds(0.5)
	if not is_inside_tree():
		return
	girl.walk_to(edge + Vector2(_side * 4.0, 0.0))
	var walked := 0.0
	while is_inside_tree() and girl.is_walking() and walked < 30.0:
		walked += get_process_delta_time()
		if kind == CompanionState.KIND_PARROT:
			animal.position = girl.get_shoulder()
		elif animal.position.distance_to(girl.position) > 30.0 and not animal.is_walking():
			animal.walk_to(girl.position - girl.facing * 22.0 + Vector2(0.0, 4.0))
		await get_tree().process_frame
	if not is_inside_tree():
		return
	var fade := create_tween().set_parallel()
	fade.tween_property(girl, "modulate:a", 0.0, 0.8)
	fade.tween_property(animal, "modulate:a", 0.0, 0.8)
	await fade.finished
	_farewell = false
	SessionLog.write("dock_farewell", {"kind": String(kind)})
	_clear()
	farewell_finished.emit()


func _until(done: Callable, timeout: float) -> void:
	var waited := 0.0
	while is_inside_tree() and not done.call() and waited < timeout:
		await get_tree().process_frame
		waited += get_process_delta_time()


func _seconds(seconds: float) -> void:
	if is_inside_tree():
		await get_tree().create_timer(seconds).timeout
