class_name DockEncounters
extends RefCounted
## Animals found on a dock (I025, A Little More Room Aboard): now and then,
## arriving in a harbour, a small cardboard box stands on the pontoon with a
## Ragdoll kitten-sized cat, a Pug or a green-cheeked conure in or beside it.
## Plain data owned by SessionState (saved with the game); changed only by
## GameSession. The scene side is DockEncounterScene.
##
## Rare, fair and not farmable: whether an arrival brings an encounter is
## decided once, at the arrival, from the game's wind seed, the harbour and the
## arrival time (so loading a save or walking in and out of the cabin never
## rolls again), with a chance that grows with every arrival without one
## (CHANCE_BASE + CHANCE_STEP per arrival, at most CHANCE_MAX: on average one
## in about every five harbour arrivals, never dozens of hours). None while
## two companions live aboard. The animal waits only while the boat lies in
## that harbour; casting off ends it quietly (it stays on its dock).
##
## Trust: no meter. A few kind gestures (TRUST_NEEDED), and it follows the
## Captain; at the companionway the Captain decides: welcome it aboard, or
## not now - then a little girl who knows it comes to fetch it.

const KINDS: Array[StringName] = [CompanionState.KIND_CAT, CompanionState.KIND_DOG, CompanionState.KIND_PARROT]
const CHANCE_BASE := 0.10
const CHANCE_STEP := 0.08
const CHANCE_MAX := 0.6
const TRUST_NEEDED := 3
const STATE_WAITING := &"waiting"
const STATE_FOLLOWING := &"following"
## How many resolved encounters are remembered (so one is never offered twice).
const MAX_RECENT := 8

## Harbour arrivals since the last encounter (raises the chance).
var arrivals_since := 0
## The animal waiting now: {"port", "kind", "since" (game time), "state",
## "trust"}, or {}.
var current := {}
## Keys ("port:since") of encounters already resolved or left behind.
var recent: Array[String] = []
var offered := 0
var adopted := 0
var declined := 0


func duplicate_state() -> DockEncounters:
	var copy := DockEncounters.new()
	copy.arrivals_since = arrivals_since
	copy.current = current.duplicate()
	copy.recent = recent.duplicate()
	copy.offered = offered
	copy.adopted = adopted
	copy.declined = declined
	return copy


## The chance that an arrival brings an encounter, after `arrivals` without.
static func chance(arrivals: int) -> float:
	return minf(CHANCE_BASE + CHANCE_STEP * maxi(arrivals, 0), CHANCE_MAX)


## Whether the arrival at `port` at game time `time` brings an encounter
## (deterministic: the same arrival always gives the same answer).
static func rolls(seed: int, port: StringName, time: float, arrivals: int) -> bool:
	var roll := float(absi(hash("dock:%d:%s:%d" % [seed, port, int(time)])) % 10000) / 10000.0
	return roll < chance(arrivals)


## Which animal it is (each kind as likely).
static func pick_kind(seed: int, port: StringName, time: float) -> StringName:
	return KINDS[absi(hash("dockkind:%d:%s:%d" % [seed, port, int(time)])) % KINDS.size()]


static func key_of(encounter: Dictionary) -> String:
	return "%s:%d" % [encounter.get("port", ""), int(encounter.get("since", 0.0))]


## Ends the current encounter and remembers it.
func resolve() -> void:
	if current.is_empty():
		return
	recent.append(key_of(current))
	while recent.size() > MAX_RECENT:
		recent.remove_at(0)
	current = {}


func to_dict() -> Dictionary:
	var data := {"arrivals_since": arrivals_since, "recent": recent.duplicate(), "offered": offered, "adopted": adopted, "declined": declined}
	if not current.is_empty():
		# A following animal is saved waiting by its box (it trusts the Captain).
		var saved := current.duplicate()
		saved.state = String(STATE_WAITING)
		saved.kind = String(saved.kind)
		saved.port = String(saved.port)
		data.current = saved
	return data


## Reads saved data; anything missing or invalid gives safe defaults (no
## encounter waiting).
static func from_dict(data: Variant) -> DockEncounters:
	var state := DockEncounters.new()
	if not data is Dictionary:
		return state
	for key in ["arrivals_since", "offered", "adopted", "declined"]:
		var value: Variant = data.get(key, 0)
		if value is int or value is float:
			state.set(key, maxi(int(value), 0))
	var saved_recent: Variant = data.get("recent", [])
	if saved_recent is Array:
		for key: Variant in saved_recent:
			if key is String:
				state.recent.append(key)
	var saved: Variant = data.get("current")
	if saved is Dictionary and StringName(str(saved.get("kind", ""))) in KINDS and saved.get("port") is String \
			and (saved.get("since") is float or saved.get("since") is int):
		var trust: Variant = saved.get("trust", 0)
		state.current = {"port": String(saved.port), "kind": StringName(str(saved.kind)), "since": float(saved.since),
			"state": STATE_WAITING, "trust": clampi(int(trust) if (trust is int or trust is float) else 0, 0, TRUST_NEEDED)}
	return state
