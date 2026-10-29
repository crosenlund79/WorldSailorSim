extends RefCounted
## I027 Tier 4, telemetry foundations: a snapshot of the real game (money and
## its sources, the boat, its care and accommodation, the inventory, voyages,
## renown, achievements, dreams); a recorder that takes one on an arrival and
## a boat bought, from real play (Copenhagen to Helsingør, then a purchase);
## its JSON lines and CSV read back; no game, no record.

var t: Node


func run(runner: Node) -> void:
	t = runner
	Simulation.auto_advance = false
	GameSession.end_session()
	t.check(CareerTelemetry.snapshot().is_empty(), "[telemetry] no game, no record")
	GameSession.test_all_boats_owned = false
	GameSession.start_new_session()
	var first := CareerTelemetry.snapshot("check")
	var sections := ["time", "finances", "boat", "inventory", "voyages", "progression"]
	t.check(sections.all(func(k: String) -> bool: return first.has(k)) and first.finances.funds == GameSession.get_funds()
		and first.boat.vessel == "arctic_wanderer_26" and first.boat.safe_guests == 3 and first.inventory.food_days > 0.0,
		"[telemetry] a snapshot holds time, finances, boat, inventory, voyages and progression, from the game itself")
	var recorder := CareerTelemetry.Recorder.new()
	recorder.start()
	GameSession.plan_route_to(&"helsingor")
	GameSession.depart()
	var guard := 0
	while GameSession.is_underway() and guard < 200:
		var voyage := GameSession.get_voyage()
		t.set_wind(fposmod(voyage.leg_bearing_at(voyage.progress_nm) + 100.0, 360.0), 12.0)
		Simulation.advance(1800.0)
		guard += 1
	var state := GameSession.get_state_snapshot()
	state.funds = 60000
	GameSession.replace_state(state)
	GameSession.buy_vessel(&"starling_33")
	recorder.mark("end")
	recorder.stop()
	var reasons: Array = recorder.records.map(func(r: Dictionary) -> String: return r.reason)
	var arrival: Dictionary = recorder.records[reasons.find("arrival")] if "arrival" in reasons else {}
	t.check(reasons.has("start") and reasons.has("arrival") and reasons.has("fleet") and reasons.back() == "end",
		"[telemetry] recorded on the game's own events: %s" % [reasons])
	t.check(not arrival.is_empty() and arrival.voyages.completed == 1 and arrival.time.location == "helsingor"
		and float(arrival.voyages.nm_total) > 15.0 and not (arrival.voyages.last as Dictionary).is_empty(),
		"[telemetry] the arrival: one voyage, %.1f nm, in Helsingør, with the voyage's own figures" % float(arrival.voyages.get("nm_total", 0.0)))
	var end: Dictionary = recorder.records.back()
	t.check((end.boat.owned as Array).has("starling_33") and int(end.finances.by_source.get("boat_purchase", 0)) == -14000
		and end.finances.net_worth_estimate == GameSession.get_funds() + 6000 + 14000,
		"[telemetry] the purchase in the books (boat_purchase %d), both boats owned, net worth estimated at list prices" % int(end.finances.by_source.get("boat_purchase", 0)))
	var base := "user://telemetry_test"
	t.check(recorder.write(base), "[telemetry] written as JSON lines and CSV")
	var lines := FileAccess.get_file_as_string(base + ".jsonl").strip_edges().split("\n")
	var csv := FileAccess.get_file_as_string(base + ".csv").strip_edges().split("\n")
	var parsed: Variant = JSON.parse_string(lines[0]) if not lines.is_empty() else null
	t.check(lines.size() == recorder.records.size() and parsed is Dictionary and int(parsed.version) == CareerTelemetry.VERSION
		and csv.size() == recorder.records.size() + 1 and csv[0].begins_with("reason,game_time"),
		"[telemetry] they read back: %d lines, a CSV with a header and %d rows" % [lines.size(), csv.size() - 1])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(base + ".jsonl"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(base + ".csv"))
	GameSession.test_all_boats_owned = true
	Simulation.auto_advance = true
	t.use_calm_wind()
	GameSession.end_session()
