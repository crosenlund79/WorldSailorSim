class_name ObjectiveProgress
extends RefCounted
## Renown and the objectives completed (Iteration 006). Plain data kept in
## SessionState and saved as the "progress" section; only GameSession writes
## it.
##
## Lifetime renown is everything ever earned and never decreases. Unpublished
## renown is the part not yet turned into money by a travel update; publishing
## lowers it, never the lifetime value.

## Rewards listed in the log, newest last.
const MAX_RECENT := 20
## Lifetime renown milestones noted as records ("renown:<n>", I024).
const RENOWN_MILESTONES: Array[int] = [250, 1000]

var lifetime_renown := 0
var unpublished_renown := 0
## Objective id (String) -> {"count": times paid, "first": game time of the
## first completion, "last_event": game time of the voyage last paid for}.
## I024: since then also, optional, "at" = where and on which boat it first
## happened ({"port": harbour id or "", "lon", "lat", "vessel"}) and "r" =
## the renown it first paid. Older records have neither: shown as "Location
## not recorded", never made up.
var completed := {}
## I024: personal records ({"key": {"value", "time", "vessel"}}), e.g. the
## best hour under sail. Optional in a save.
var records := {}
## The latest rewards: {"id", "title", "reward", "time"}.
var recent: Array[Dictionary] = []
## Travel updates published, the renown they used and the euros they paid.
var publications := 0
var published_renown := 0
var published_euros := 0


func duplicate_progress() -> ObjectiveProgress:
	var copy := ObjectiveProgress.new()
	copy.lifetime_renown = lifetime_renown
	copy.unpublished_renown = unpublished_renown
	copy.completed = completed.duplicate(true)
	for entry in recent:
		copy.recent.append(entry.duplicate())
	copy.publications = publications
	copy.published_renown = published_renown
	copy.published_euros = published_euros
	copy.records = records.duplicate(true)
	return copy


func is_completed(id: StringName) -> bool:
	return completed.has(String(id))


func get_count(id: StringName) -> int:
	return int(completed.get(String(id), {}).get("count", 0))


## Whether `objective` may pay for the voyage that ended at `event_time`: a
## one-time objective only if never completed; a repeatable one only for a
## voyage later than the last one it paid for. So no voyage is ever paid twice,
## whatever is evaluated again.
func can_pay(objective: Dictionary, event_time: float) -> bool:
	var entry: Variant = completed.get(String(objective.id))
	if entry == null:
		return true
	return bool(objective.repeatable) and event_time > float(entry.last_event)


## Pays `reward` renown for objective `id` completed by the voyage that ended
## at `event_time` (GameSession only).
## `at` (I024): where it happened (see `completed`), kept for the first time.
func award(id: StringName, title: String, reward: int, event_time: float, at := {}) -> void:
	var key := String(id)
	if not completed.has(key):
		completed[key] = {"count": 0, "first": event_time, "last_event": event_time, "r": reward}
		if not at.is_empty():
			completed[key].at = at.duplicate()
	completed[key].count = int(completed[key].count) + 1
	completed[key].last_event = event_time
	var before := lifetime_renown
	lifetime_renown += reward
	unpublished_renown += reward
	# I024: renown milestones are kept as records of when (and where) they were passed.
	for milestone in RENOWN_MILESTONES:
		if before < milestone and lifetime_renown >= milestone:
			mark(StringName("renown:%d" % milestone), event_time, at)
	recent.append({"id": key, "title": title, "reward": reward, "time": event_time})
	while recent.size() > MAX_RECENT:
		recent.remove_at(0)


## Records that `id` happened at `event_time` without paying renown (a Go
## Ashore outing repeated, Iteration 12). Same record as award().
func mark(id: StringName, event_time: float, at := {}) -> void:
	var key := String(id)
	if not completed.has(key):
		completed[key] = {"count": 0, "first": event_time, "last_event": event_time}
		if not at.is_empty():
			completed[key].at = at.duplicate()
	completed[key].count = int(completed[key].count) + 1
	completed[key].last_event = event_time


func to_dict() -> Dictionary:
	return {
		"lifetime_renown": lifetime_renown,
		"unpublished_renown": unpublished_renown,
		"completed": completed.duplicate(true),
		"recent": recent.duplicate(true),
		"publications": publications,
		"published_renown": published_renown,
		"published_euros": published_euros,
		"records": records.duplicate(true),
	}


static func from_dict(data: Variant, errors: Array[String]) -> ObjectiveProgress:
	if not data is Dictionary:
		errors.append("missing renown and objectives")
		return null
	var progress := ObjectiveProgress.new()
	for key in ["lifetime_renown", "unpublished_renown", "publications", "published_renown", "published_euros"]:
		if not _is_number(data.get(key)) or float(data.get(key)) < 0.0:
			errors.append("invalid renown (%s)" % key)
			return null
	progress.lifetime_renown = int(data.lifetime_renown)
	progress.unpublished_renown = int(data.unpublished_renown)
	if progress.unpublished_renown > progress.lifetime_renown:
		errors.append("unpublished renown exceeds lifetime renown")
		return null
	progress.publications = int(data.publications)
	progress.published_renown = int(data.published_renown)
	progress.published_euros = int(data.published_euros)
	var completed: Variant = data.get("completed")
	var recent: Variant = data.get("recent", [])
	if not completed is Dictionary or not recent is Array:
		errors.append("invalid objective records")
		return null
	for id: Variant in completed:
		var entry: Variant = completed[id]
		if not id is String or not entry is Dictionary or not _is_number(entry.get("count")) or int(entry.count) < 1 \
				or not _is_number(entry.get("first")) or not _is_number(entry.get("last_event")):
			errors.append("invalid objective record")
			return null
		progress.completed[id] = {"count": int(entry.count), "first": float(entry.first), "last_event": float(entry.last_event)}
		# I024 (optional): where it happened, and the renown it paid.
		var at: Variant = entry.get("at")
		if at is Dictionary and _is_number(at.get("lon")) and _is_number(at.get("lat")):
			progress.completed[id].at = {"port": str(at.get("port", "")), "lon": float(at.lon), "lat": float(at.lat), "vessel": str(at.get("vessel", ""))}
		if _is_number(entry.get("r")):
			progress.completed[id].r = int(entry.r)
	for entry: Variant in recent:
		if not entry is Dictionary or not entry.get("id") is String or not _is_number(entry.get("reward")) or not _is_number(entry.get("time")):
			errors.append("invalid renown record")
			return null
		progress.recent.append({"id": String(entry.id), "title": str(entry.get("title", entry.id)), "reward": int(entry.reward),
			"time": float(entry.time)})
	while progress.recent.size() > MAX_RECENT:
		progress.recent.remove_at(0)
	var records: Variant = data.get("records", {})
	if records is Dictionary:
		for key: Variant in records:
			var record: Variant = records[key]
			if key is String and record is Dictionary and _is_number(record.get("value")) and _is_number(record.get("time")):
				progress.records[key] = {"value": float(record.value), "time": float(record.time), "vessel": str(record.get("vessel", ""))}
	return progress


## A personal record (I024): keeps `value` when it beats the one kept.
## Returns true when it is a new record.
func note_record(key: String, value: float, time: float, vessel: StringName) -> bool:
	if records.has(key) and float(records[key].value) >= value:
		return false
	records[key] = {"value": value, "time": time, "vessel": String(vessel)}
	return true


func get_record(key: String) -> Dictionary:
	return records.get(key, {})


static func _is_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
