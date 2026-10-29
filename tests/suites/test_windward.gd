extends RefCounted
## I027 Tier 1, the cost of the wind: sailing to windward. CourseMaker's
## choice (straight, beating, gybing; each boat its own angles), the
## simulation beating up a real leg (tacks at the lane's edge, never on land,
## no flip-flopping, progress honestly less than the distance sailed), a tack
## by hand, a wind shift, the same result in long and short steps, the course
## through a save and an old save without it, and an ETA that knows a
## waypoint to windward takes longer than a straight line.

var t: Node


func run(runner: Node) -> void:
	t = runner
	Simulation.auto_advance = false
	_test_course_maker()
	_test_boat_angles()
	_test_beating()
	_test_manual_tack()
	_test_wind_shift()
	_test_steps()
	_test_save()
	_test_eta()
	_test_boats_upwind()
	Simulation.auto_advance = true
	t.use_calm_wind()
	GameSession.end_session()


func _profile(id: StringName) -> VesselProfile:
	var definition := VesselCatalog.get_default().get_vessel(id)
	return definition.performance if definition.performance else VesselProfile.get_default()


func _test_course_maker() -> void:
	var p := _profile(&"arctic_wanderer_26")
	var up := CourseMaker.plan(p, 0.0, 0.0, 12.0)
	t.check(up.zigzag and float(up.best.delta) >= 36.0 and float(up.best.delta) <= 64.0 and float(up.best.vmc) > 1.5,
		"[course] dead to windward in 12 kn: a beat, %d° off the wind, %.1f kn made good" % [roundi(float(up.best.delta)), float(up.best.vmc)])
	t.check(float(up.direct.speed) == 0.0, "[course] the direct course into the wind makes nothing")
	var reach := CourseMaker.plan(p, 0.0, 90.0, 12.0)
	t.check(not reach.zigzag and is_equal_approx(float(reach.direct.speed), float(reach.direct.vmc)), "[course] a beam reach is sailed straight")
	var run := CourseMaker.plan(p, 180.0, 0.0, 12.0)
	t.check(run.zigzag and float(run.best.vmc) > float(run.direct.vmc) and CourseMaker.is_downwind(float(run.best.heading), 0.0),
		"[course] dead downwind the broad reaches gybing make more than the run (%.2f vs %.2f kn)" % [float(run.best.vmc), float(run.direct.vmc)])
	var calm := CourseMaker.plan(p, 0.0, 0.0, 0.0)
	t.check(not calm.zigzag, "[course] in a calm there is nothing to tack for")
	t.check(is_equal_approx(CourseMaker.lane_nm(100.0), CourseMaker.LANE_MAX_NM) and is_equal_approx(CourseMaker.lane_nm(0.1), CourseMaker.LANE_MIN_NM)
		and CourseMaker.lane_nm(5.0) < CourseMaker.lane_nm(15.0), "[course] the lane narrows as the waypoint nears")


## Each boat keeps its own character to windward.
func _test_boat_angles() -> void:
	var tri := CourseMaker.plan(_profile(&"petrel_36"), 0.0, 0.0, 14.0)
	var cat := CourseMaker.plan(_profile(&"halcyon_40"), 0.0, 0.0, 14.0)
	var sloop := CourseMaker.plan(_profile(&"arctic_wanderer_26"), 0.0, 0.0, 14.0)
	t.check(float(tri.best.delta) < float(cat.best.delta), "[boats] the trimaran points higher than the catamaran (%d° vs %d°)" % [roundi(float(tri.best.delta)), roundi(float(cat.best.delta))])
	t.check(float(tri.best.vmc) > float(sloop.best.vmc) and float(tri.best.vmc) > float(cat.best.vmc),
		"[boats] made good to windward in 14 kn: the trimaran best (%.1f kn; 26 ft sloop %.1f, catamaran %.1f)" % [float(tri.best.vmc), float(sloop.best.vmc), float(cat.best.vmc)])
	t.check(_profile(&"petrel_36").tack_loss_s < _profile(&"arctic_wanderer_26").tack_loss_s and _profile(&"arctic_wanderer_26").tack_loss_s < _profile(&"halcyon_40").tack_loss_s,
		"[boats] a tack costs the trimaran least, the catamaran most")


## A voyage whose first open leg lies dead to windward: the bearing of the
## leg the boat is on once clear of the harbour.
func _upwind_voyage(boat: StringName, kn := 13.0) -> float:
	GameSession.start_new_session()
	t.board(boat)
	GameSession.plan_route_to(&"gothenburg")
	t.set_wind(0.0, kn)
	GameSession.depart()
	# Clear of the harbour (where the boat keeps to its line), then the wind
	# straight down the leg ahead.
	for i in 24:
		Simulation.advance(300.0)
	var voyage := GameSession.get_voyage()
	var bearing := voyage.leg_bearing_at(voyage.progress_nm)
	t.set_wind(bearing, kn)
	Simulation.evaluate_propulsion(true)
	return bearing


## Five minutes on, with the wind kept dead on the nose of the leg the boat is
## on (the route bends; the test wants a steady beat).
func _beat_step(kn := 13.0) -> void:
	var voyage := GameSession.get_voyage()
	if voyage:
		var bearing := voyage.leg_bearing_at(voyage.progress_nm)
		if absf(WindField.relative_angle(bearing, WindField.get_default().sample(GameSession.get_vessel_position(), GameSession.get_game_time()).from_deg)) > 1.0:
			t.set_wind(bearing, kn)
	Simulation.advance(300.0)


func _test_beating() -> void:
	var bearing := _upwind_voyage(&"arctic_wanderer_26")
	var router := SeaRouter.get_default()
	var start := GameSession.get_voyage()
	var tack_times: Array[float] = []
	var last_tacks := start.tack_count
	var afloat := true
	var max_off := 0.0
	var sailing := 0
	var samples := 0
	for i in 72:  # 6 hours in 5-minute steps
		if not GameSession.is_underway():
			break
		_beat_step()
		var c := GameSession.get_voyage_course()
		if int(c.tack_count) != last_tacks:
			tack_times.append(GameSession.get_game_time())
			last_tacks = int(c.tack_count)
		afloat = afloat and router.is_afloat(GameSession.get_vessel_position())
		max_off = maxf(max_off, absf(float(c.cross_track_nm)))
		samples += 1
		sailing += 0 if GameSession.get_propulsion().is_motoring() else 1
	var end := GameSession.get_voyage()
	var gained := end.progress_nm - start.progress_nm
	var sailed := end.sailed_nm - start.sailed_nm
	t.check(tack_times.size() >= 2, "[beat] beating up a %03d° leg in 13 kn: the autopilot tacks (%d times in 6 h)" % [roundi(bearing), tack_times.size()])
	t.check(sailing >= samples * 0.8, "[beat] under sail, not motoring into it (%d of %d samples)" % [sailing, samples])
	t.check(gained > 0.0 and sailed > gained * 1.2, "[beat] honest progress: %.1f nm towards the waypoint for %.1f nm sailed" % [gained, sailed])
	t.check(max_off <= CourseMaker.LANE_MAX_NM + 1.0 and max_off > 0.2, "[beat] off the line within the lane (at most %.1f nm)" % max_off)
	t.check(afloat, "[beat] never on land while tacking")
	var shortest := INF
	for i in range(1, tack_times.size()):
		shortest = minf(shortest, tack_times[i] - tack_times[i - 1])
	t.check(tack_times.size() < 2 or shortest >= CourseMaker.MIN_LANE_TACK_S - 1.0, "[beat] no flip-flopping: tacks at least %d min apart (shortest %d min)" % [
		roundi(CourseMaker.MIN_LANE_TACK_S / 60.0), roundi(shortest / 60.0)])
	var heading := Simulation.get_current_heading()
	var wind_now := WindField.get_default().sample(GameSession.get_vessel_position(), GameSession.get_game_time()).from_deg
	t.check(absf(WindField.relative_angle(heading, wind_now)) >= 35.0, "[beat] the boat points off the wind (%03d° in wind from %03d°), the deck and sails with it" % [roundi(heading), roundi(wind_now)])
	var p := GameSession.get_propulsion()
	t.check(p.sails_set() and absf(p.true_wind_angle) >= 35.0 and absf(p.true_wind_angle) <= 70.0, "[beat] close hauled on the instruments (%d°)" % roundi(absf(p.true_wind_angle)))
	var data := InstrumentData.read()
	t.check(data.get_value("heading").contains("tack") and data.get_value("tack").contains("made good"), "[instruments] the tack and the progress made good: '%s' / '%s'" % [data.get_value("heading"), data.get_value("tack")])


func _test_manual_tack() -> void:
	_upwind_voyage(&"arctic_wanderer_26")
	for i in 30:
		_beat_step()
		if int(GameSession.get_voyage_course().tack_side) != 0 and not GameSession.get_propulsion().is_motoring():
			break
	var before := GameSession.get_voyage_course()
	var side_before := PropulsionState.wind_side(GameSession.get_propulsion().true_wind_angle)
	if not t.check(int(before.tack_side) != 0, "(setup) beating"):
		return
	t.check(Simulation.manual_tack() == "", "[hand] Tack now")
	var after := GameSession.get_voyage_course()
	t.check(int(after.tack_side) == -int(before.tack_side) and int(after.tack_count) == int(before.tack_count) + 1
		and float(after.tack_loss_left_s) > 0.0, "[hand] the other tack at once, with the time a tack costs")
	t.check(PropulsionState.wind_side(GameSession.get_propulsion().true_wind_angle) != side_before, "[hand] the wind now on the other side (%s -> %s)" % [side_before,
		PropulsionState.wind_side(GameSession.get_propulsion().true_wind_angle)])
	Simulation.advance(900.0)
	t.check(int(GameSession.get_voyage_course().tack_side) == int(after.tack_side) or float(GameSession.get_voyage_course().cross_track_nm) * int(after.tack_side) >= 0.0,
		"[hand] the autopilot keeps the tack it was given")
	# Not a tack to change on a reach.
	t.set_wind(fposmod(GameSession.get_voyage().leg_bearing_at(GameSession.get_voyage_progress_nm()) + 90.0, 360.0), 13.0)
	Simulation.advance(1200.0)
	var reach_refusal := Simulation.manual_tack()
	t.check(reach_refusal != "" if int(GameSession.get_voyage_course().tack_side) == 0 else true, "[hand] on a reach there is no tack to change ('%s')" % reach_refusal)


func _test_wind_shift() -> void:
	var bearing := _upwind_voyage(&"arctic_wanderer_26")
	Simulation.advance(2400.0)
	var side := int(GameSession.get_voyage_course().tack_side)
	if not t.check(side != 0, "(setup) beating"):
		return
	# A lasting shift that heads this tack and frees the other one.
	t.set_wind(fposmod(bearing - side * 30.0, 360.0), 13.0)
	var changed := false
	for i in 12:
		Simulation.advance(300.0)
		if int(GameSession.get_voyage_course().tack_side) != side:
			changed = true
			break
	t.check(changed, "[shift] a 30° shift: the autopilot takes the lifted tack within the hour")


## Long and short steps sail the same zigzag.
func _test_steps() -> void:
	var results := []
	for step: float in [5.0, 60.0, 4.0 * 3600.0]:
		_upwind_voyage(&"arctic_wanderer_26")
		var elapsed := 0.0
		while elapsed < 4.0 * 3600.0 - 1e-6:
			Simulation.advance(step)
			elapsed += step
		var c := GameSession.get_voyage_course()
		results.append([GameSession.get_voyage_progress_nm(), float(c.cross_track_nm), int(c.tack_count)])
	var same := true
	for r in results:
		same = same and absf(float(r[0]) - float(results[0][0])) < 1e-6 and absf(float(r[1]) - float(results[0][1])) < 1e-6 and int(r[2]) == int(results[0][2])
	t.check(same, "[steps] the same zigzag in 5 s, 1 min and one 4-hour step %s" % [results])


func _test_save() -> void:
	_upwind_voyage(&"arctic_wanderer_26")
	Simulation.advance(3000.0)
	var state := GameSession.get_state_snapshot()
	var data := state.to_dict()
	var errors: Array[String] = []
	var loaded := SessionState.from_dict(JSON.parse_string(JSON.stringify(data)), errors)
	t.check(loaded != null and errors.is_empty(), "[save] a voyage mid-tack saves and loads %s" % [errors])
	if loaded:
		t.check(is_equal_approx(loaded.voyage.cross_track_nm, state.voyage.cross_track_nm) and loaded.voyage.tack_side == state.voyage.tack_side
			and loaded.voyage.tack_count == state.voyage.tack_count and loaded.vessel_position.distance_to(state.vessel_position) < 1e-5,
			"[save] off the line by %.2f nm on the same tack, at the same position" % state.voyage.cross_track_nm)
	# A voyage saved before I027 has no course: it sails its line.
	var old: Dictionary = JSON.parse_string(JSON.stringify(data))
	old.navigation.voyage.erase("course")
	var line: Dictionary = old.navigation.voyage
	var old_errors: Array[String] = []
	var voyage := Voyage.from_dict(line, PortCatalog.get_default(), old_errors)
	t.check(voyage != null and voyage.cross_track_nm == 0.0 and voyage.tack_side == 0 and voyage.course_leg == -1,
		"[save] an older voyage loads on its line, not tacking %s" % [old_errors])


## The estimate for a whole leg to windward against the time the boat
## actually takes to beat up it.
func _test_eta() -> void:
	_upwind_voyage(&"arctic_wanderer_26")
	_beat_step()
	var voyage := GameSession.get_voyage()
	var leg_end := voyage.progress_nm + voyage.remaining_leg_nm()
	var start := GameSession.get_game_time()
	var estimate := Simulation.estimate_route_seconds(voyage.route.path, voyage.progress_nm, start, leg_end)
	var straight := voyage.remaining_leg_nm() / _profile(&"arctic_wanderer_26").max_sail_speed_kn * 3600.0
	var guard := 0
	while GameSession.is_underway() and GameSession.get_voyage_progress_nm() < leg_end - 1e-6 and guard < 2000:
		_beat_step()
		guard += 1
	var actual := GameSession.get_game_time() - start
	t.check(estimate > straight * 1.5, "[eta] a %.0f nm leg dead to windward is estimated at %s, not the straight line's %s" % [
		leg_end - voyage.progress_nm, Simulation.format_duration(estimate), Simulation.format_duration(straight)])
	t.check(absf(actual - estimate) / actual < 0.15, "[eta] and the beat takes about that: %s actual (%.0f %% off)" % [
		Simulation.format_duration(actual), absf(actual - estimate) / actual * 100.0])


## The same 6 hours to windward in three different boats.
func _test_boats_upwind() -> void:
	var made := {}
	var engine := {}
	for boat: StringName in [&"petrel_36", &"arctic_wanderer_26", &"halcyon_40"]:
		_upwind_voyage(boat, 14.0)
		var from := GameSession.get_voyage_progress_nm()
		var motored := 0
		for i in 72:
			if not GameSession.is_underway():
				break
			_beat_step(14.0)
			motored += 1 if GameSession.get_propulsion().is_motoring() else 0
		made[boat] = GameSession.get_voyage_progress_nm() - from
		engine[boat] = motored
	# Under sail the trimaran out-points the sloop; the catamaran, worst to
	# windward, may well motor (its engine is the most capable).
	t.check(int(engine[&"petrel_36"]) <= 12 and int(engine[&"arctic_wanderer_26"]) <= 12 and float(made[&"petrel_36"]) > float(made[&"arctic_wanderer_26"]),
		"[boats] six hours to windward in 14 kn: trimaran %.1f nm, 26 ft %.1f nm, catamaran %.1f nm made good (motoring %d / %d / %d of 72 samples)" % [
		float(made[&"petrel_36"]), float(made[&"arctic_wanderer_26"]), float(made[&"halcyon_40"]), engine[&"petrel_36"], engine[&"arctic_wanderer_26"], engine[&"halcyon_40"]])
