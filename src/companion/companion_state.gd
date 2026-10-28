class_name CompanionState
extends RefCounted
## Who lives aboard with the player, and where they are resting right now.
## Plain data owned by SessionState (saved with the game); changed only via
## GameSession. The cabin's ShipCompanion node only presents it.
##
## Deliberately small: a kind, a resting spot and when it next moves. "Kind"
## is not limited to animals; a later crew member would be another kind with
## its own spots (and, if ever needed, its own data next to this).
##
## Resting spots change occasionally, on the game clock: every 2-5 game hours
## the companion moves (instantly) to another spot. Both the next spot and the
## interval are picked deterministically from the kind and a move counter, so
## the result depends only on game time: the same at 1x, 20x or while
## sleeping, and identical after loading.
##
## Iteration 18: the companion can come up on deck with the captain while the
## boat is moored or safely at anchor (`area`, and which of the deck's few
## resting places, `deck_spot`). Its cabin schedule runs on as before; on deck
## it rests at its deck spot. Optional in a save: absent means the cabin.

## I024 (The Company We Keep): the kinds keep their saved ids; "cat" is drawn
## as a Ragdoll and "dog" as a Pug, so older saves map onto the new looks.
## "parrot" is a green-cheeked conure: free aboard, perching and flying.
const KIND_CAT := &"cat"
const KIND_DOG := &"dog"
const KIND_PARROT := &"parrot"
const KINDS: Array[StringName] = [KIND_CAT, KIND_DOG, KIND_PARROT]
const DEFAULT_KIND := KIND_CAT
## Player-chosen gender (I024; optional, "" = not said).
const GENDER_FEMALE := &"female"
const GENDER_MALE := &"male"
const GENDER_OTHER := &"other"
const GENDERS: Array[StringName] = [GENDER_FEMALE, GENDER_MALE, GENDER_OTHER]
## Longest name kept (characters).
const MAX_NAME_LENGTH := 20

## Resting spot ids per kind. The ids are semantic and shared by every
## vessel: each cabin scene places a marker with the same name under
## Layout/CompanionSpots, so the companion keeps its spot when the player
## changes boats and the positions belong to the vessel's layout, not here.
## Markers are placed off the interaction points and walkways; the companion
## has no collision either way.
const SPOTS := {
	KIND_CAT: [&"settee", &"nav_station", &"v_berth"],
	KIND_DOG: [&"cabin_floor", &"companionway", &"seating"],
	# The parrot perches: on the chart table, the back of the settee, by the
	# berth and on the companionway steps (the cabins' shared markers).
	KIND_PARROT: [&"nav_station", &"settee", &"v_berth", &"companionway"],
}
## I024: where it is found when the Captain wakes - at the berth (the cat and
## dog at its foot, the parrot on its perch beside it). Valid for every kind,
## although only the cat and the parrot rest there by habit.
const WAKE_SPOT := &"v_berth"
## Every spot id a cabin must provide (see VesselDefinition.validate()).
const ALL_SPOT_IDS: Array[StringName] = [&"settee", &"nav_station", &"v_berth", &"cabin_floor", &"companionway", &"seating"]
const MIN_REST_SECONDS := 2.0 * 3600.0
const MAX_REST_SECONDS := 5.0 * 3600.0
## Loading a game far in the future of its schedule never loops for long.
const MAX_CATCH_UP_MOVES := 64

var kind: StringName = DEFAULT_KIND
var spot: StringName = &""
## Game time at which the companion next changes its resting spot.
var next_move_time := 0.0
## How many times it has moved (drives the deterministic choices).
var moves := 0
const AREA_CABIN := &"cabin"
const AREA_DECK := &"deck"
## I024: ashore with the Captain (on the pontoon / exploring the harbour).
## Only while moored; the boat cannot cast off until it is back aboard.
const AREA_SHORE := &"shore"
const AREAS: Array[StringName] = [AREA_CABIN, AREA_DECK, AREA_SHORE]
var area: StringName = AREA_CABIN
## I024: the name and gender the player chose ("" when none: no default name
## is ever made up).
var name := ""
var gender: StringName = &""
## Which deck resting place (0 aft, 1 amidships, 2 forward); see DeckCompanionSpots.
var deck_spot := 0


static func create(companion_kind: StringName, now: float, companion_name := "", companion_gender: StringName = &"") -> CompanionState:
	var state := CompanionState.new()
	state.kind = companion_kind if companion_kind in KINDS else DEFAULT_KIND
	state.name = clean_name(companion_name)
	state.gender = companion_gender if companion_gender in GENDERS else &""
	state.spot = get_spot_ids(state.kind)[0]
	state.next_move_time = now + state._rest_interval()
	return state


static func get_spot_ids(companion_kind: StringName) -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(SPOTS.get(companion_kind, []))
	return ids


## "cat" / "dog" / "parrot" as shown to the player.
static func display_name(companion_kind: StringName) -> String:
	match companion_kind:
		KIND_DOG:
			return "dog"
		KIND_PARROT:
			return "parrot"
	return "cat"


## The breed shown when choosing ("Ragdoll cat", "Pug", ...), untranslated key.
static func species_name(companion_kind: StringName) -> String:
	match companion_kind:
		KIND_DOG:
			return "Pug"
		KIND_PARROT:
			return "Green-cheeked conure"
	return "Ragdoll cat"


## A name as kept: trimmed, single-line, at most MAX_NAME_LENGTH characters.
static func clean_name(raw: String) -> String:
	var text := raw.replace("\n", " ").replace("\t", " ").strip_edges()
	while text.contains("  "):
		text = text.replace("  ", " ")
	return text.substr(0, MAX_NAME_LENGTH).strip_edges()


func has_name() -> bool:
	return name != ""


## Found by the berth on waking (I024): the spot becomes WAKE_SPOT and its
## next move comes a normal rest later. Below, wherever it was.
func wake_by_berth(now: float) -> void:
	area = AREA_CABIN
	spot = WAKE_SPOT
	next_move_time = now + _rest_interval()


## Moves on to new resting spots for every move due by `now`. Returns true
## when the spot changed.
func advance_to(now: float) -> bool:
	var before := spot
	var catch_up := 0
	while now >= next_move_time and catch_up < MAX_CATCH_UP_MOVES:
		catch_up += 1
		moves += 1
		var others := get_spot_ids(kind)
		others.erase(spot)  # (after waking by the berth a dog may be on none of its own)
		spot = others[_pick(moves, others.size())]
		next_move_time += _rest_interval()
	if now >= next_move_time:  # very long gap: resume the schedule from now
		next_move_time = now + _rest_interval()
	return spot != before


func duplicate_state() -> CompanionState:
	var copy := CompanionState.new()
	copy.kind = kind
	copy.spot = spot
	copy.next_move_time = next_move_time
	copy.moves = moves
	copy.area = area
	copy.deck_spot = deck_spot
	copy.name = name
	copy.gender = gender
	return copy


func to_dict() -> Dictionary:
	return {"kind": String(kind), "spot": String(spot), "next_move_time": next_move_time, "moves": moves,
		"area": String(area), "deck_spot": deck_spot, "name": name, "gender": String(gender)}


## Validates saved data. Returns null (with reasons in `errors`) when invalid.
static func from_dict(data: Variant, errors: Array[String]) -> CompanionState:
	if not data is Dictionary:
		errors.append("companion data is not an object")
		return null
	var companion_kind := StringName(str(data.get("kind", "")))
	if companion_kind not in KINDS:
		errors.append("unknown companion kind")
		return null
	var companion_spot := StringName(str(data.get("spot", "")))
	if companion_spot not in get_spot_ids(companion_kind) and companion_spot != WAKE_SPOT:
		errors.append("unknown companion resting spot")
		return null
	var next_move: Variant = data.get("next_move_time")
	var move_count: Variant = data.get("moves")
	if not (next_move is float or next_move is int) or not is_finite(float(next_move)) \
			or not (move_count is float or move_count is int) or int(move_count) < 0:
		errors.append("invalid companion schedule")
		return null
	var state := CompanionState.new()
	state.kind = companion_kind
	state.spot = companion_spot
	state.next_move_time = float(next_move)
	state.moves = int(move_count)
	var saved_area := StringName(str(data.get("area", AREA_CABIN)))
	state.area = saved_area if saved_area in AREAS else AREA_CABIN
	if state.area == AREA_SHORE:
		state.area = AREA_DECK  # loading: it has come back aboard (GameSession brings it below if needed)
	var saved_spot: Variant = data.get("deck_spot", 0)
	state.deck_spot = clampi(int(saved_spot), 0, 2) if (saved_spot is int or saved_spot is float) else 0
	# I024 fields, optional (older saves: no name, no gender).
	var saved_name: Variant = data.get("name", "")
	state.name = clean_name(saved_name) if saved_name is String else ""
	var saved_gender := StringName(str(data.get("gender", "")))
	state.gender = saved_gender if saved_gender in GENDERS else &""
	return state


func _rest_interval() -> float:
	# Whole minutes, so the schedule survives any JSON round trip exactly.
	return roundf(lerpf(MIN_REST_SECONDS, MAX_REST_SECONDS, _pick(moves * 7 + 3, 1000) / 999.0) / 60.0) * 60.0


## Deterministic pseudo-random integer in [0, count) for this kind and `n`.
func _pick(n: int, count: int) -> int:
	return absi(hash("%s:%d" % [kind, n])) % count
