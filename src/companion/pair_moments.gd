class_name PairMoments
extends Node
## Two companions aboard (I025, A Little More Room Aboard): now and then they
## notice each other - a visit and a greeting, a look across the cabin, a nap
## at the same time - different for every pairing (cat and dog, cat and
## conure, dog and conure, two of a kind). Never predatory: the cat watches
## the bird, it never stalks it. Rare (a moment every MOMENT_SECONDS of real
## time at most), no meters, no needs. Presentation only: nothing is saved
## and the companions' places stay GameSession's.
##
## Built by BoatArea for the cabin and the deck; works on the area's two
## ShipCompanion nodes (no searching per frame). Visits happen in the cabin
## only (on deck they stay at their safe places and greet from there).

## Seconds of real time between moments (random in this range).
const MOMENT_SECONDS := Vector2(80.0, 180.0)
const VISIT_GAP := 34.0

## What each does when they greet: [first kind's clip, second kind's clip],
## keyed "first+second".
const GREETINGS := {
	"cat+dog": [&"alert", &"tail_wag"],
	"cat+parrot": [&"alert", &"head_turn"],
	"dog+parrot": [&"tail_wag", &"ruffle"],
	"cat+cat": [&"groom", &"groom"],
	"dog+dog": [&"tail_wag", &"tail_wag"],
	"parrot+parrot": [&"preen", &"head_turn"],
}
## The moments each pairing has (keys as above): "visit" (the first named
## goes to the other; "visit_back": the second goes to the first), "watch"
## (the first looks across at the other), "nap" (both settle down).
const MOMENTS := {
	"cat+dog": ["visit_back", "watch", "nap"],
	"cat+parrot": ["visit_back", "watch"],
	"dog+parrot": ["visit_back", "watch"],
	"cat+cat": ["visit", "nap"],
	"dog+dog": ["visit", "visit_back", "nap"],
	"parrot+parrot": ["visit", "watch"],
}

var area: BoatArea
var nodes: Array[ShipCompanion] = []
var _left := 0.0
var _busy := false
var _rng := RandomNumberGenerator.new()


func setup(boat_area: BoatArea) -> void:
	area = boat_area
	nodes = area.get_companion_nodes()
	_rng.randomize()
	_left = _rng.randf_range(MOMENT_SECONDS.x, MOMENT_SECONDS.y)


## The pair's key: the two kinds in a fixed order, and whether `a` came second.
static func key_of(a: StringName, b: StringName) -> Array:
	var order: Array[StringName] = [CompanionState.KIND_CAT, CompanionState.KIND_DOG, CompanionState.KIND_PARROT]
	var swapped := order.find(a) > order.find(b)
	return ["%s+%s" % ([b, a] if swapped else [a, b]), swapped]


## The clips two companions greet each other with: [a's, b's].
static func greeting(a: StringName, b: StringName) -> Array[StringName]:
	var key := key_of(a, b)
	var clips: Array = GREETINGS.get(key[0], [&"alert", &"alert"])
	var out: Array[StringName] = [StringName(clips[0]), StringName(clips[1])]
	if key[1]:
		out.reverse()
	return out


func _process(delta: float) -> void:
	if _busy or nodes.size() < 2 or GameSession.get_companion_count() < 2:
		return
	_left -= delta
	if _left > 0.0:
		return
	_left = _rng.randf_range(MOMENT_SECONDS.x, MOMENT_SECONDS.y)
	if ready_for_moment():
		play_moment()


## Both shown here, resting (not walking or asleep), the Captain awake and
## time at its normal pace.
func ready_for_moment() -> bool:
	if nodes.size() < 2 or GameSession.is_asleep() or GameSession.get_time_scale() > 1:
		return false
	for node in nodes:
		if not node.is_visible_in_tree() or node.is_walking() or not node.is_sprite_mode() \
				or node.pose == CompanionVisualSet.POSE_SLEEPING or node.get_companion_state() == null:
			return false
		if node.get_companion_state().area == CompanionState.AREA_SHORE:
			return false
	return true


## Plays one of the pair's moments (`which`: a moment name, or "" for a
## random one). Returns the moment played, or "".
func play_moment(which := "") -> String:
	if _busy or not ready_for_moment():
		return ""
	var a := nodes[0]
	var b := nodes[1]
	var key := key_of(a.kind, b.kind)
	var moments: Array = MOMENTS.get(key[0], ["watch"])
	var moment: String = which if which != "" and which in moments else String(moments[_rng.randi() % moments.size()])
	# The pairing's "first" and "second" (key order), as nodes.
	var first := b if key[1] else a
	var second := a if key[1] else b
	SessionLog.write("pair_moment", {"pair": key[0], "moment": moment})
	match moment:
		"visit":
			_visit(first, second)
		"visit_back":
			_visit(second, first)
		"nap":
			for node in nodes:
				node.set_pose(CompanionVisualSet.POSE_SLEEPING)
		_:
			_watch(first, second)
	return moment


## `mover` goes over to `host`; they greet; it goes back to its place.
## On deck they greet from where they are.
func _visit(mover: ShipCompanion, host: ShipCompanion) -> void:
	_busy = true
	var home := mover.position
	if not mover.on_deck:
		var toward := mover.position - host.position
		toward = toward.normalized() if toward.length() > 1.0 else Vector2.RIGHT
		mover.walk_to(host.position + toward * VISIT_GAP)
		await _walked(mover)
	if _gone(mover, host):
		_busy = false
		return
	mover.facing = signf(host.position.x - mover.position.x) if absf(host.position.x - mover.position.x) > 2.0 else mover.facing
	host.facing = -mover.facing
	var clips := greeting(mover.kind, host.kind)
	mover.respond(clips[0])
	host.respond(clips[1])
	await get_tree().create_timer(2.8).timeout
	if not _gone(mover, host) and not mover.on_deck and not mover.is_walking():
		mover.walk_to(home)
		await _walked(mover)
	_busy = false


## `watcher` looks across at `other` (who carries on).
func _watch(watcher: ShipCompanion, other: ShipCompanion) -> void:
	if absf(other.position.x - watcher.position.x) > 2.0:
		watcher.facing = signf(other.position.x - watcher.position.x)
	watcher.respond(CompanionVisualSet.POSE_ALERT)
	other.respond(greeting(watcher.kind, other.kind)[1])


func _gone(a: ShipCompanion, b: ShipCompanion) -> bool:
	return not is_inside_tree() or not is_instance_valid(a) or not is_instance_valid(b)


func _walked(node: ShipCompanion) -> void:
	var waited := 0.0
	while is_inside_tree() and is_instance_valid(node) and node.is_walking() and waited < 15.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
