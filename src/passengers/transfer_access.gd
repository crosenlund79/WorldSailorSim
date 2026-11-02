class_name TransferAccess
extends RefCounted
## How far a harbour is from onward travel (I028 Tier 3), for agreeing another
## harbour with a passenger when the planned one cannot be reached in time.
## Honest bands from data/passengers/transfer_access.json - a curated band for
## the harbours listed there, otherwise an estimate from the catalogue, shown
## as an estimate. No taxis, trains or flights are simulated.

const DATA_PATH := "res://data/passengers/transfer_access.json"

static var _data: Dictionary


static func _catalogue() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_data = parsed if parsed is Dictionary else {"bands": [], "harbours": {}}
	return _data


## {"id", "label" (translated), "rank" (0 best), "estimate" (bool)} for a harbour.
static func band(port_id: StringName) -> Dictionary:
	var curated: Dictionary = _catalogue().get("harbours", {})
	var id := ""
	var estimate := false
	if curated.has(String(port_id)):
		id = String(curated[String(port_id)])
	else:
		estimate = true
		var port := PortCatalog.get_default().get_port(port_id)
		if port == null:
			id = "far"
		elif port.island and port.importance >= 2:
			id = "ferry"
		else:
			id = {1: "near", 2: "regional"}.get(port.importance, "far")
	for b: Dictionary in _catalogue().get("bands", []):
		if b.id == id:
			return {"id": id, "label": Loc.t(String(b.label)), "rank": int(b.rank), "estimate": estimate}
	return {"id": id, "label": id, "rank": 2, "estimate": estimate}


## "Airport within the hour" or "Airport one to three hours away (estimate)".
static func describe(port_id: StringName) -> String:
	var b := band(port_id)
	return "%s%s" % [b.label, Loc.t(" (estimate)") if b.estimate else ""]
