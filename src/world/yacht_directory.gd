class_name YachtDirectory
extends RefCounted
## The yacht directory (I028 Tier 6): a searchable list of the sailing
## world's notable yachts as the public knows them - not a live tracker. Each
## entry shows the yacht's last *public* report: the most recent of its
## departures and arrivals that its crew posted on the Traveller Network
## (TravellerNetwork.post_for, the same posts the feed shows). A yacht that
## never posted is "unknown"; a report older than STALE_DAYS is flagged stale,
## because the yacht may well have moved on. Where a yacht really is now is
## only known within AIS range (AisReceiver.notable_contacts_at), and the two
## are kept apart on purpose.

const STALE_DAYS := 10.0


## Every notable yacht, matching `query` (name, model, skipper or port; any
## case), by name: [{"id", "name", "model", "type", "skipper", "skipper_id",
## "report": {} or {"t", "kind", "port", "to", "status"}, "age_days", "stale",
## "unknown", "expedition"}].
static func entries(world: WorldState, now: float, query := "") -> Array:
	var out: Array = []
	var q := query.strip_edges().to_lower()
	for y: Dictionary in WorldChronicle.data().get("yachts", []):
		var id := String(y.id)
		var skipper := WorldChronicle.skipper_of(id)
		var report := last_report(world, id, now)
		var entry := {"id": id, "name": String(y.name), "model": String(y.get("model", "")), "type": Loc.t(String(y.get("type", ""))),
			"skipper": String(skipper.get("name", "")), "skipper_id": String(skipper.get("id", "")), "report": report,
			"unknown": report.is_empty(), "age_days": (now - float(report.t)) / WorldChronicle.DAY if not report.is_empty() else -1.0,
			"expedition": String((world.yachts.get(id, {}) as Dictionary).get("expedition", ""))}
		entry.stale = not report.is_empty() and float(entry.age_days) > STALE_DAYS
		if q != "":
			var where := TravellerNetwork._place(String(report.get("port", ""))) if not report.is_empty() else ""
			var hay := ("%s %s %s %s %s" % [entry.name, entry.model, entry.skipper, where, entry.type]).to_lower()
			if not q in hay:
				continue
		out.append(entry)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.name) < String(b.name))
	return out


## The yacht's most recent posted departure or arrival up to `now`, or {}.
static func last_report(world: WorldState, yacht_id: String, now: float) -> Dictionary:
	for i in range(world.events.size() - 1, -1, -1):
		var e: Dictionary = world.events[i]
		if String(e.get("yacht", "")) != yacht_id or float(e.t) > now or not String(e.kind) in ["depart", "arrive", "expedition_complete", "expedition_announced"]:
			continue
		if TravellerNetwork.post_for(e).is_empty():
			continue
		var status := "departed" if e.kind == "depart" else ("announced" if e.kind == "expedition_announced" else "in_port")
		return {"t": float(e.t), "kind": String(e.kind), "port": String(e.get("port", "")), "to": String(e.get("to", "")), "status": status}
	return {}
