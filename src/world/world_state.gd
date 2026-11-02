class_name WorldState
extends RefCounted
## The world beyond the Captain (I028 Tiers 5-6), saved under "world"
## (optional: an older save starts a fresh, empty world on load):
##   - events: the one persistent world-event ledger (WorldChronicle), in time
##     order, never rewritten - departures, arrivals, expeditions, books,
##     meetings, the Captain's own published works and notable voyages. The
##     most recent MAX_EVENTS are kept; everything they changed is also in
##     renown (lasting totals) and the yachts' last reports, so trimming the
##     oldest never changes the rankings or the directory;
##   - yachts: where each notable yacht is (a harbour, or one leg under way)
##     and its last public report;
##   - renown: lasting renown per person (notable travellers, the population,
##     "captain" for the Captain's published works and notable voyages);
##   - writing: the Captain's travel writing (project, published works,
##     experience, and whether the old game project was migrated);
##   - issues: Sails & Sights, each monthly issue frozen when published;
##   - encounters, relations, invitations: the Captain's place in this world.

const MAX_EVENTS := 900

var started_at := 0.0
var generated_until := 0.0
var seq := 0
var events: Array = []
var yachts := {}
var renown := {}
var writing := {"project": {}, "works": [], "xp": 0, "migrated": false}
var issues: Array = []
var encounters := {}
var relations := {}
var invitations: Array = []


func next_seq() -> int:
	seq += 1
	return seq


func add_event(event: Dictionary) -> Dictionary:
	event.seq = next_seq()
	events.append(event)
	for id: Variant in (event.get("renown", {}) as Dictionary):
		renown[String(id)] = int(renown.get(String(id), 0)) + int(event.renown[id])
	while events.size() > MAX_EVENTS:
		events.pop_front()
	return event


func duplicate_world() -> WorldState:
	return WorldState.from_dict(to_dict())


## As the save holds it: numbers as JSON gives them back (so a game's state
## reads the same before saving and after loading).
func to_dict() -> Dictionary:
	return JSON.parse_string(JSON.stringify(_raw_dict(), "", true, true))  # full precision, as SaveManager writes


func _raw_dict() -> Dictionary:
	return {"started_at": started_at, "generated_until": generated_until, "seq": seq, "events": events.duplicate(true),
		"yachts": yachts.duplicate(true), "renown": renown.duplicate(), "writing": writing.duplicate(true), "issues": issues.duplicate(true),
		"encounters": encounters.duplicate(), "relations": relations.duplicate(), "invitations": invitations.duplicate(true)}


static func _num(v: Variant, fallback := 0.0) -> float:
	return float(v) if v is int or v is float else fallback


static func from_dict(data: Variant) -> WorldState:
	var w := WorldState.new()
	if not data is Dictionary:
		return w
	var d: Dictionary = data
	w.started_at = _num(d.get("started_at"))
	w.generated_until = _num(d.get("generated_until"))
	w.seq = int(_num(d.get("seq")))
	for key in ["events", "issues", "invitations"]:
		var list: Variant = d.get(key, [])
		if list is Array:
			w.set(key, (list as Array).filter(func(e: Variant) -> bool: return e is Dictionary).map(func(e: Dictionary) -> Dictionary: return e.duplicate(true)))
	for key in ["yachts", "encounters", "relations"]:
		if d.get(key) is Dictionary:
			w.set(key, (d[key] as Dictionary).duplicate(true))
	if d.get("renown") is Dictionary:
		for id: Variant in d.renown:
			w.renown[String(id)] = int(_num(d.renown[id]))
	if d.get("writing") is Dictionary:
		var wr: Dictionary = d.writing
		w.writing = {"project": wr.get("project", {}) if wr.get("project") is Dictionary else {},
			"works": wr.get("works", []) if wr.get("works") is Array else [], "xp": int(_num(wr.get("xp"))), "migrated": wr.get("migrated", false) == true}
	return w
