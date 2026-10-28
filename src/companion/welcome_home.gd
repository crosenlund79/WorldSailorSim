class_name WelcomeHome
extends Node
## The first minute aboard of an adopted companion (I025, A Little More Room
## Aboard): plays once, in the cabin, the first time it is seen there, and is
## never replayed (CompanionState.welcomed, saved). Short and quiet, by kind:
## the cat explores a little, stretches and settles; the Pug trots about,
## wags and sniffs; the conure flutters to a perch, chirps and flies on
## before settling. When another companion already lives aboard and is in
## the cabin, the newcomer goes to it first and they greet each other, then
## both settle (side by side when they share a spot; ShipCompanion._paired).
## Presentation only: the companions' state does not change. It runs as a
## child node of the companion, so leaving the cabin simply ends it.


## Plays the welcome of `node`'s companion (call when the cabin shows it).
## `other` is the companion already aboard (or null).
static func play(node: ShipCompanion, other: ShipCompanion) -> void:
	var companion := node.get_companion_state()
	if companion == null or companion.welcomed or not node.is_sprite_mode():
		return
	var moment := WelcomeHome.new()
	moment.name = "WelcomeHome"
	node.add_child(moment)
	moment._run(node, other, companion)


func _run(node: ShipCompanion, other: ShipCompanion, companion: CompanionState) -> void:
	GameSession.mark_companion_welcomed(companion.id)  # once, even if it is cut short
	SessionLog.write("companion_welcome", {"id": companion.id, "kind": String(companion.kind)})
	var rest := node.position
	var entry := node.get_spot_position(&"companionway")
	node.position = entry
	node.pace = 1.6 if companion.kind == CompanionState.KIND_DOG else 1.2
	if other and other.visible and other.get_companion_state() and other.get_companion_state().area == CompanionState.AREA_CABIN:
		await _greet(node, other)
	else:
		match companion.kind:
			CompanionState.KIND_PARROT:
				await _parrot(node, entry, rest)
			CompanionState.KIND_DOG:
				await _dog(node, entry, rest)
			_:
				await _cat(node, entry, rest)
	if not _alive(node):
		queue_free()
		return
	node.pace = 1.0
	node.walk_to(rest)
	await _walked(node)
	if _alive(node):
		node.set_pose(CompanionVisualSet.POSE_RESTING)
	queue_free()


## Other places in this cabin worth a look (a little way towards them).
func _look_points(node: ShipCompanion, entry: Vector2, rest: Vector2) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var spots := node.get_node_or_null(node.spots_path)
	if spots:
		for marker in spots.get_children():
			var at := (marker as Node2D).position
			if at.distance_to(entry) > 40.0 and at.distance_to(rest) > 40.0:
				points.append(entry.lerp(at, 0.7))
	if points.is_empty():
		points.append(entry.lerp(rest, 0.5))
	return points.slice(0, 2)


func _cat(node: ShipCompanion, entry: Vector2, rest: Vector2) -> void:
	for at in _look_points(node, entry, rest):
		node.walk_to(at)
		await _walked(node)
		if not _alive(node):
			return
		node.respond(CompanionVisualSet.POSE_ALERT)  # a careful look round
		await _wait(node, 1.6)
	if not _alive(node):
		return
	node.respond(CompanionVisualSet.POSE_STRETCHING)
	await _wait(node, 2.2)


func _dog(node: ShipCompanion, entry: Vector2, rest: Vector2) -> void:
	for at in _look_points(node, entry, rest):
		node.walk_to(at)
		await _walked(node)
		if not _alive(node):
			return
		node.respond(CompanionVisualSet.POSE_TAIL_WAG)
		await _wait(node, 1.4)
		if not _alive(node):
			return
		node.respond(CompanionVisualSet.POSE_ALERT)  # a good sniff
		await _wait(node, 1.0)


func _parrot(node: ShipCompanion, entry: Vector2, rest: Vector2) -> void:
	var points := _look_points(node, entry, rest)
	node.walk_to(points[0])
	await _walked(node)
	if not _alive(node):
		return
	node.respond(CompanionVisualSet.POSE_ALERT)  # a chirp
	await _wait(node, 1.4)
	if not _alive(node):
		return
	node.respond(CompanionVisualSet.POSE_RUFFLE)
	await _wait(node, 1.6)


## Goes to the companion already aboard; they greet (a look, a wag, a
## chirp), then both settle.
func _greet(node: ShipCompanion, other: ShipCompanion) -> void:
	var toward := (node.position - other.position).normalized()
	node.walk_to(other.position + toward * 34.0)
	await _walked(node)
	if not _alive(node) or not is_instance_valid(other):
		return
	other.facing = signf(node.position.x - other.position.x) if absf(node.position.x - other.position.x) > 2.0 else other.facing
	node.facing = -other.facing
	var greet := PairMoments.greeting(node.kind, other.kind)
	node.respond(greet[0])
	other.respond(greet[1])
	await _wait(node, 2.4)


func _alive(node: ShipCompanion) -> bool:
	return is_inside_tree() and is_instance_valid(node) and node.is_inside_tree()


func _walked(node: ShipCompanion) -> void:
	var waited := 0.0
	while _alive(node) and node.is_walking() and waited < 20.0:
		await get_tree().process_frame
		waited += get_process_delta_time()


func _wait(node: ShipCompanion, seconds: float) -> void:
	if _alive(node):
		await get_tree().create_timer(seconds).timeout
