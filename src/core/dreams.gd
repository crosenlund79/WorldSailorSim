class_name Dreams
extends RefCounted
## Dreams of the Sea (Between Horizons, I027 Tier 4): the Captain's lifetime
## ambitions, a modest journal on the laptop. The dreams are data
## (data/progression/dreams.json); this class reads them and says whether one
## has come true, from what really happened - the Captain's Log (harbours
## visited, the longest passage) and the boats owned. Nothing is invented:
## the Captain chooses which dreams to pursue (at most MAX_PURSUED), in any
## order, and each comes true by itself. Dreams that need I028's systems (a
## travel book, renown as a world traveller) are shown but stay inactive.
## Pure and static; the Captain's choices and fulfilled dreams live in
## SessionState.dreams (GameSession).

const DATA_PATH := "res://data/progression/dreams.json"
const MAX_PURSUED := 3
const KIND_LONGEST := "longest_passage"
const KIND_NORTH := "visit_north"
const KIND_REGION := "visit_region"
const KIND_OCEAN_BOAT := "own_ocean_boat"
const KIND_LATER := "later"

static var _data: Array[Dictionary] = []


## Every dream, in the journal's order: {"id", "title", "text", "kind", ...}.
static func all() -> Array[Dictionary]:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary:
			for dream: Dictionary in (parsed as Dictionary).get("dreams", []):
				_data.append(dream)
	return _data


static func get_dream(id: StringName) -> Dictionary:
	for dream in all():
		if StringName(dream.id) == id:
			return dream
	return {}


## False for a dream that waits for a later system (I028).
static func is_active(dream: Dictionary) -> bool:
	return String(dream.get("kind", "")) != KIND_LATER


## True when `dream` has come true: from the Captain's Log and the boats owned.
static func is_met(dream: Dictionary, log: CaptainsLog, owned: Array[StringName]) -> bool:
	match String(dream.get("kind", "")):
		KIND_LONGEST:
			return log != null and log.get_longest_nm() >= float(dream.get("nm", 0.0))
		KIND_NORTH:
			return _visited_where(log, func(port: PortData) -> bool: return port.latitude >= float(dream.get("lat", 90.0))) >= int(dream.get("count", 1))
		KIND_REGION:
			var regions: Array = dream.get("regions", [])
			return _visited_where(log, func(port: PortData) -> bool: return port.region in regions) >= int(dream.get("count", 1))
		KIND_OCEAN_BOAT:
			return owned.any(func(id: StringName) -> bool: return Accommodation.suits_passage(id, Accommodation.PASSAGE_OCEAN))
	return false


## How far along a dream is, in words for the journal ("2 of 3 harbours"),
## or "" when there is nothing to count.
static func progress_text(dream: Dictionary, log: CaptainsLog) -> String:
	match String(dream.get("kind", "")):
		KIND_LONGEST:
			var longest := log.get_longest_nm() if log else 0.0
			return Loc.format("Longest passage so far: %.0f nm", longest) if longest > 0.0 else ""
		KIND_NORTH:
			var n := _visited_where(log, func(port: PortData) -> bool: return port.latitude >= float(dream.get("lat", 90.0)))
			return Loc.t("%d of %d harbours") % [mini(n, int(dream.get("count", 1))), int(dream.get("count", 1))] if int(dream.get("count", 1)) > 1 else ""
	return ""


static func _visited_where(log: CaptainsLog, test: Callable) -> int:
	if log == null:
		return 0
	var n := 0
	var catalog := PortCatalog.get_default()
	for id in log.get_visited_ids():
		var port := catalog.get_port(id)
		if port and test.call(port):
			n += 1
	return n
