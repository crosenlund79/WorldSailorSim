extends RefCounted
## I019, The Captain's Watch: maritime traffic and the radar, collision
## awareness and its warnings (fair, once, interrupting sleep and Long
## Passage), anchor-drag awareness levels, and VHF calls with their once-only
## thanks across save and load.

var t: Node
var app: Node


func run(runner: Node) -> void:
	t = runner
	app = runner.get("app")
	Simulation.auto_advance = false
	GameSession.start_new_session()
	SeaRouter.get_default()  # the sea (traffic keeps to navigable water)
	_test_traffic_model()
	_test_cpa()
	_test_alerts_on_passage()
	_test_sleep_and_passage_interrupt()
	_test_radar()
	_test_anchor_levels()
	_test_vhf()
	_test_vhf_in_simulation()
	t.use_calm_wind()
	Simulation.auto_advance = true
	GameSession.end_session()


func _depart(from: StringName, to: StringName) -> String:
	var state := GameSession.get_state_snapshot()
	state.location_id = from
	state.vessel_status = SessionState.STATUS_MOORED
	state.vessel_position = PortCatalog.get_default().get_port(from).get_geo_position()
	state.voyage = null
	state.anchor = AnchorState.new()
	GameSession.replace_state(state)
	var error := GameSession.plan_route_to(to)
	if error == "":
		error = GameSession.depart()
	return error


## A deep copy through the save format (what a save and load would give).
static func _round_trip() -> SessionState:
	var errors: Array[String] = []
	var data: Variant = JSON.parse_string(JSON.stringify(GameSession.get_state_snapshot().to_dict()))
	return SessionState.from_dict(data, errors)


func _test_traffic_model() -> void:
	var model := TrafficModel.get_default()
	var copenhagen := PortCatalog.get_default().get_port(&"copenhagen").get_geo_position()
	var time := Time.get_unix_time_from_datetime_string("2026-06-01T10:00:00")
	var a := model.vessels_near(copenhagen + Vector2(0.3, 0.2), time, 3, 30.0)
	var fresh := TrafficModel.new()
	var b := fresh.vessels_near(copenhagen + Vector2(0.3, 0.2), time, 3, 30.0)
	var same := a.size() == b.size()
	for i in mini(a.size(), b.size()):
		same = same and a[i].id == b[i].id and (a[i].geo as Vector2).is_equal_approx(b[i].geo)
	t.check(same and not a.is_empty(), "[traffic] deterministic: the same ships in the same places, asked twice (%d within 30 nm of Copenhagen)" % a.size())
	var router := SeaRouter.get_loaded()
	var on_water := a.all(func(v: Dictionary) -> bool: return router == null or router.is_point_navigable(v.geo))
	t.check(on_water, "[traffic] every vessel is on navigable water")
	# Bounded: busy waters at most MAX_PER_CELL per cell and window; the open
	# ocean has few.
	var ocean := model.vessels_near(Vector2(-35.0, 45.0), time, 3, 12.0)
	var tracks := model._cell_tracks(12, 55, floori(time / TrafficModel.WINDOW_SECONDS), 3)
	t.check(tracks.size() <= TrafficModel.MAX_PER_CELL and ocean.size() <= 2,
		"[traffic] bounded: %d tracks in a busy cell (max %d), %d ships within 12 nm mid-Atlantic" % [tracks.size(), TrafficModel.MAX_PER_CELL, ocean.size()])
	var later := model.vessels_near(copenhagen + Vector2(0.3, 0.2), time + 600.0, 3, 30.0)
	var moved := false
	for v in later:
		for w in a:
			if v.id == w.id and not (v.geo as Vector2).is_equal_approx(w.geo):
				moved = true
	t.check(moved, "[traffic] ships move along their tracks over time")
	var start := Time.get_ticks_usec()
	for i in 50:
		model.vessels_near(copenhagen, time + i * 300.0, 3, Simulation.RADAR_RANGE_NM)
	var ms := (Time.get_ticks_usec() - start) / 50000.0
	t.check(ms < 2.0, "[traffic] a radar query is cheap (%.3f ms)" % ms)


func _test_cpa() -> void:
	# Head-on, 4 nm apart, 6 kn each: meet in 20 minutes, dead ahead.
	var head_on := TrafficModel.approach(Vector2(0.0, 4.0), 180.0, 6.0, 0.0, 6.0)
	t.check(absf(head_on.cpa_nm) < 1e-6 and is_equal_approx(head_on.tcpa_h, 4.0 / 12.0), "[cpa] head-on: passes 0 nm off in 20 min (%.3f nm, %.3f h)" % [head_on.cpa_nm, head_on.tcpa_h])
	# Same course and speed: the distance never changes.
	var parallel := TrafficModel.approach(Vector2(1.0, 0.0), 90.0, 6.0, 90.0, 6.0)
	t.check(is_equal_approx(parallel.cpa_nm, 1.0) and parallel.tcpa_h == 0.0, "[cpa] same course and speed: the distance stays")
	# A ship crossing ahead from the east, already past: negative TCPA.
	var past := TrafficModel.approach(Vector2(-2.0, -1.0), 270.0, 10.0, 0.0, 5.0)
	t.check(past.tcpa_h < 0.0, "[cpa] a ship already past has a negative time to CPA")
	t.check_eq(Simulation.risk_level({"cpa_nm": 0.2, "tcpa_h": 0.3, "distance_nm": 2.0}), Simulation.RISK_DANGER, "[cpa] 0.2 nm in 18 min: collision risk")
	t.check_eq(Simulation.risk_level({"cpa_nm": 0.6, "tcpa_h": 0.5, "distance_nm": 3.0}), Simulation.RISK_CAUTION, "[cpa] 0.6 nm in 30 min: caution")
	t.check_eq(Simulation.risk_level({"cpa_nm": 3.0, "tcpa_h": 0.5, "distance_nm": 4.0}), Simulation.RISK_NEARBY, "[cpa] passing wide within 6 nm: nearby")
	t.check_eq(Simulation.risk_level({"cpa_nm": 0.1, "tcpa_h": 0.2, "distance_nm": 2.0}, false), Simulation.RISK_NEARBY,
		"[cpa] at anchor or moored a close ship is only nearby (only a moving boat can be on a collision course)")


## A long passage through busy waters: every alert is fair (well ahead) and
## comes once per ship.
func _test_alerts_on_passage() -> void:
	t.use_calm_wind()
	t.set_wind(240.0, 12.0)
	var alerts: Array[Dictionary] = []
	var listener := func(info: Dictionary) -> void: alerts.append(info)
	Simulation.traffic_alert.connect(listener)
	var hours := 0.0
	for route in [[&"copenhagen", &"gothenburg"], [&"kiel", &"copenhagen"], [&"malmo", &"reykjavik"]]:
		if not t.check(_depart(route[0], route[1]) == "", "(setup) underway %s to %s" % route):
			continue
		var leg := 0.0
		while GameSession.is_underway() and leg < 150.0:
			Simulation.advance(1800.0)
			leg += 0.5
		hours += leg
	Simulation.traffic_alert.disconnect(listener)
	var ids := {}
	var fair := true
	var duplicate := false
	for info in alerts:
		duplicate = duplicate or ids.has(info.id)
		ids[info.id] = true
		fair = fair and float(info.tcpa_h) >= 0.15 and String(info.text).begins_with("Collision risk")
	t.check(not alerts.is_empty(), "[alerts] (setup) busy and long routes bring collision risks (%d in %.0f h)" % [alerts.size(), hours])
	t.check(not duplicate, "[alerts] each ship is announced once (%d alerts in %.1f h)" % [alerts.size(), hours])
	t.check(fair, "[alerts] every alert comes with time to act (at least 9 minutes before the closest point): %s" % [
		alerts.map(func(i: Dictionary) -> int: return roundi(float(i.tcpa_h) * 60.0))])
	t.check(alerts.size() <= hours / 10.0, "[alerts] warnings are rare, not a nuisance (%d in %.0f h)" % [alerts.size(), hours])


## Sleep and Long Passage stop for a collision risk; after a load the same
## ship is not announced again.
func _test_sleep_and_passage_interrupt() -> void:
	t.set_wind(240.0, 12.0)
	var routes := [[&"copenhagen", &"kiel"], [&"copenhagen", &"gothenburg"], [&"copenhagen", &"aarhus"], [&"kiel", &"copenhagen"], [&"malmo", &"reykjavik"]]
	var found := false
	for route in routes:
		if _depart(route[0], route[1]) != "":
			continue
		var alert := [{}]
		var listener := func(info: Dictionary) -> void: alert[0] = info
		Simulation.traffic_alert.connect(listener)
		var before := _round_trip()
		var steps := 0
		while GameSession.is_underway() and alert[0].is_empty() and steps < 200:
			before = _round_trip()
			Simulation.advance(1800.0)
			steps += 1
		Simulation.traffic_alert.disconnect(listener)
		if alert[0].is_empty():
			continue
		found = true
		var after := _round_trip()
		# Back to before the alert, and sleep: woken by it.
		GameSession.replace_state(before)
		var slept := Simulation.sleep(8.0)
		t.check(slept.stopped_by == Simulation.STOP_TRAFFIC or slept.stopped_by == Simulation.STOP_WARNING,
			"[sleep] a collision risk wakes the captain (%s after %s)" % [slept.stopped_by, Simulation.format_duration(slept.elapsed_seconds)])
		# Long Passage stops for it too.
		GameSession.replace_state(before)
		var reasons: Array[StringName] = []
		var on_stop := func(reason: StringName, _text: String) -> void: reasons.append(reason)
		Simulation.passage_interrupted.connect(on_stop)
		Simulation.passage_rate = 3600.0
		var guard := 0
		while reasons.is_empty() and guard < 600:
			Simulation._passage_tick(0.1)
			guard += 1
		Simulation.passage_rate = 0.0
		Simulation.passage_interrupted.disconnect(on_stop)
		t.check(not reasons.is_empty() and reasons[0] in [Simulation.STOP_TRAFFIC, Simulation.STOP_WARNING],
			"[passage] Long Passage stops for a collision risk (%s)" % [reasons])
		# Loaded after the alert: the same ship is not announced again.
		GameSession.replace_state(after)
		var again := [0]
		var count := func(info: Dictionary) -> void:
			if info.id == alert[0].id:
				again[0] += 1
		Simulation.traffic_alert.connect(count)
		Simulation.advance(3600.0)
		Simulation.traffic_alert.disconnect(count)
		t.check_eq(again[0], 0, "[save] after a load the same ship is not announced twice")
		break
	t.check(found, "[sleep] (setup) a route with a collision risk was found")


func _test_radar() -> void:
	t.check_eq(RadarPanel.describe([] as Array[Dictionary]), "No vessels in range. A clear sea.", "[radar] an empty scope says so")
	var risks: Array[Dictionary] = [{"kind": &"ferry", "distance_nm": 2.4, "bearing": 45.0, "tcpa_h": 0.3, "cpa_nm": 0.2, "risk": Simulation.RISK_DANGER}]
	var text := RadarPanel.describe(risks)
	t.check(text.contains("Ferry 2.4 nm NE") and text.contains("passes 0.2 nm off in 18 min") and text.contains("Collision risk"),
		"[radar] a risk is described with what to do: \"%s\"" % text.replace("\n", " / "))
	t.check(RadarPanel.colour_for(Simulation.RISK_DANGER) != RadarPanel.colour_for(Simulation.RISK_CAUTION)
		and RadarPanel.colour_for(Simulation.RISK_CAUTION) != RadarPanel.colour_for(Simulation.RISK_NEARBY), "[radar] three distinct concern colours")
	# Switched on at sea, then moored: it must not stay up where its Q-menu item
	# (the only way to close it) is gone; it comes back on the next voyage.
	if _depart(&"copenhagen", &"kiel") == "":
		var scope := RadarPanel.new()
		scope.on_deck = func() -> bool: return true
		RadarPanel.shown = true
		var at_sea := scope.should_show()
		var moored := GameSession.get_state_snapshot()
		moored.location_id = &"copenhagen"
		moored.vessel_status = SessionState.STATUS_MOORED
		moored.voyage = null
		GameSession.replace_state(moored)
		t.check(at_sea and not scope.should_show(), "[radar] switched on at sea, it goes away on mooring (no Radar item in harbour)")
		t.check(_depart(&"copenhagen", &"kiel") == "" and scope.should_show(), "[radar] and it is back on the next voyage")
		RadarPanel.shown = false
		scope.free()
	if app == null or app.get("hud") == null:
		return
	var panel: RadarPanel = app.hud.radar_panel
	t.check(panel != null and panel.get_parent() != null, "[radar] the HUD has a radar instrument")


func _test_anchor_levels() -> void:
	t.set_wind(240.0, 8.0)
	if _depart(&"copenhagen", &"kiel") != "":
		t.check(false, "(setup) underway for anchoring")
		return
	var near := false
	for i in 200:
		if GameSession.evaluate_anchorage().ok:
			near = true
			break
		Simulation.advance(300.0)
	if not t.check(near and GameSession.drop_anchor(3, 0.3).error == "", "(setup) at anchor"):
		return
	var alarms: Array[String] = []
	var listener := func(info: Dictionary) -> void: alarms.append(String(info.level))
	GameSession.anchor_alarm.connect(listener)
	var notices: Array[String] = []
	var heard := func(text: String) -> void: notices.append(text)
	GameSession.notice.connect(heard)
	var tick := GameSession.get_game_time()
	var holdings := []
	for wind in [8.0, 40.0, 40.0, 45.0, 40.0, 8.0, 40.0]:
		t.set_wind(240.0, wind)
		Simulation.invalidate_estimates()
		tick += 300.0
		GameSession.apply_anchor_check(tick)
		holdings.append([wind, String(GameSession.get_anchor().holding), GameSession.get_anchor().alarm_level])
	GameSession.anchor_alarm.disconnect(listener)
	GameSession.notice.disconnect(heard)
	var rose := not alarms.is_empty()
	var no_repeat := true
	for i in range(1, alarms.size()):
		no_repeat = no_repeat and alarms[i] != alarms[i - 1]
	t.check(rose and no_repeat and alarms.size() <= 2, "[anchor] alarms only when the concern rises, never the same twice in a row: %s (%s)" % [alarms, holdings])
	var good_again := notices.filter(func(n: String) -> bool: return n.contains("holding well again")).size()
	t.check(good_again <= 1, "[anchor] \"holding well again\" is said once (%d)" % good_again)
	# Save compatibility: an older anchor record (no level) takes it from the alarm.
	var old := GameSession.get_anchor().to_dict()
	old.erase("alarm_level")
	old.erase("good_since")
	old.alarm = true
	old.holding = "dragging"
	var errors: Array[String] = []
	var restored := AnchorState.from_dict(old, errors)
	t.check(errors.is_empty() and restored.alarm_level == 2, "[anchor] an older save's dragging alarm loads as level 2 (%s)" % [errors])
	var trip := AnchorState.from_dict(GameSession.get_anchor().to_dict(), errors)
	t.check(trip.alarm_level == GameSession.get_anchor().alarm_level, "[anchor] the alarm level survives save and load")
	GameSession.raise_anchor()


func _test_vhf() -> void:
	# The calls are a pure function of the voyage and slot.
	var calls := 0
	var assists := 0
	for slot in range(1000, 1400):
		var a := VhfRadio.call_for_slot(1.79e9, slot, 3, false)
		var b := VhfRadio.call_for_slot(1.79e9, slot, 3, false)
		if not a.is_empty():
			calls += 1
			assists += 1 if a.kind == VhfRadio.KIND_ASSIST else 0
			if JSON.stringify(a) != JSON.stringify(b):
				t.check(false, "[vhf] deterministic per slot")
				return
	t.check(calls > 40 and calls < 160 and assists > 10, "[vhf] calls are occasional: %d in 400 slots of 6 h (%d asking for assistance)" % [calls, assists])
	t.set_wind(240.0, 10.0)
	if _depart(&"copenhagen", &"gothenburg") != "":
		return
	Simulation.advance(3600.0)
	var call := {"id": "test:1", "kind": VhfRadio.KIND_ASSIST, "slot": 1, "due": GameSession.get_game_time(), "vessel": "Freja",
		"problem": 0, "distance_nm": 3.2, "bearing": 90.0, "hours": 2, "renown": 4, "money": 120, "hazardous": false}
	t.check(VhfRadio.describe(call).contains("Freja") and VhfRadio.describe_commitment(call).contains("2 hours"), "[vhf] the call says what is asked: \"%s\"" % VhfRadio.describe(call))
	var renown := GameSession.get_lifetime_renown()
	var funds := GameSession.get_funds()
	var declined := GameSession.answer_vhf(call, false)
	t.check(not declined.answered and GameSession.get_lifetime_renown() == renown and String(declined.text).contains("Another vessel"), "[vhf] declining is fine: another vessel answers, no penalty")
	var saved := _round_trip()
	var answered := GameSession.answer_vhf(call, true)
	t.check(answered.answered and GameSession.get_lifetime_renown() == renown + 4 and GameSession.get_funds() == funds + 120 and GameSession.is_standing_by(),
		"[vhf] answering an assist call: standing by, +4 renown, +120 (%s)" % answered.text)
	var position := GameSession.get_vessel_position()
	var progress := GameSession.get_voyage_progress_nm()
	Simulation.advance(3600.0)
	t.check(GameSession.get_vessel_position() == position and is_equal_approx(GameSession.get_voyage_progress_nm(), progress), "[vhf] standing by, the boat stays where it is")
	var twice := GameSession.answer_vhf(call, true)
	t.check(not twice.answered and GameSession.get_lifetime_renown() == renown + 4, "[vhf] the same call cannot be answered twice")
	# Saved and loaded after answering: still paid once; standing by goes on.
	var after := _round_trip()
	GameSession.replace_state(after)
	t.check(GameSession.is_standing_by() and not GameSession.answer_vhf(call, true).answered and GameSession.get_lifetime_renown() == renown + 4,
		"[save] after a load the boat still stands by and the thanks are not paid again")
	var notices: Array[String] = []
	var heard := func(text: String) -> void: notices.append(text)
	GameSession.notice.connect(heard)
	Simulation.advance(3 * 3600.0)
	GameSession.notice.disconnect(heard)
	t.check(not GameSession.is_standing_by() and GameSession.get_voyage_progress_nm() > progress + 1.0 and notices.any(func(n: String) -> bool: return n.contains("coastguard")),
		"[vhf] when the coastguard arrives the voyage goes on by itself (%.1f nm on)" % (GameSession.get_voyage_progress_nm() - progress))
	# Loaded from before answering: it can be answered once, there.
	GameSession.replace_state(saved)
	t.check(GameSession.can_answer_vhf(call), "[save] loaded from before answering, the call is still open")
	var late := call.duplicate()
	late.id = "test:2"
	late.due = GameSession.get_game_time() - VhfRadio.ANSWER_WITHIN_SECONDS - 60.0
	t.check(not GameSession.can_answer_vhf(late) and not GameSession.answer_vhf(late, true).answered, "[vhf] a call not answered within an hour is taken by another vessel")
	var forecast := call.duplicate()
	forecast.id = "test:3"
	forecast.kind = VhfRadio.KIND_FORECAST
	forecast.renown = 1
	forecast.money = 0
	var r0 := GameSession.get_lifetime_renown()
	var shared := GameSession.answer_vhf(forecast, true)
	t.check(shared.answered and GameSession.get_lifetime_renown() == r0 + 1 and not GameSession.is_standing_by(), "[vhf] sharing the forecast: +1 renown, the voyage goes on")


## Calls come by themselves on a long voyage, once per slot, across a load.
func _test_vhf_in_simulation() -> void:
	t.set_wind(240.0, 12.0)
	if _depart(&"copenhagen", &"reykjavik") != "":
		t.check(false, "(setup) underway to Reykjavik")
		return
	var heard: Array[Dictionary] = []
	var listener := func(call: Dictionary) -> void: heard.append(call)
	Simulation.vhf_call.connect(listener)
	var hours := 0.0
	var reloaded := false
	while GameSession.is_underway() and hours < 240.0:
		Simulation.advance(1800.0)
		hours += 0.5
		if not reloaded and heard.size() == 1:
			GameSession.replace_state(_round_trip())  # a save and load right after the first call
			reloaded = true
		if GameSession.is_standing_by():
			GameSession.end_standby()
	Simulation.vhf_call.disconnect(listener)
	var slots := {}
	var duplicate := false
	for call in heard:
		duplicate = duplicate or slots.has(call.slot)
		slots[call.slot] = true
	t.check(not heard.is_empty() and not duplicate, "[vhf] calls come by themselves, never twice (%d in %.0f h, slots %s)" % [heard.size(), hours, slots.keys()])
