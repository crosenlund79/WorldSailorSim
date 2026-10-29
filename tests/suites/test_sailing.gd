extends RefCounted
## Automatic sail/engine control, wind-driven voyages on the single timeline
## (independent of step size, time acceleration and sleeping), ETA, weather
## warnings with variable speed, and saving/loading propulsion state.

const STEP := 300.0
const BEAM := 100.0  # wind angle used for controller tests (no spinnaker)

var t: Node
var profile: VesselProfile
var changes: Array = []


func run(runner: Node) -> void:
	t = runner
	profile = VesselProfile.get_default()
	Simulation.auto_advance = false
	_test_initial_choice()
	_test_sustained_poor_wind()
	_test_stall()
	_test_brief_dips()
	_test_engine_stops()
	_test_hysteresis()
	_test_no_cycling()
	_test_course_change_resets()
	_test_spinnaker_state()
	_test_step_independence()
	_test_eta()
	WeatherFixtures.use([WeatherFixtures.gale("test_strong_winds", Vector2(12.2, 54.78), 9.0, 26.0,
		SessionState.get_start_time() - 3600.0, 24.0 * 365.0)])
	_test_warnings_with_wind()
	WeatherFixtures.clear()
	_test_course_change_at_sea()
	_test_save_and_load()
	_test_migration_from_v2()
	Simulation.auto_advance = true
	t.use_calm_wind()
	GameSession.end_session()


# --- Controller (pure) -----------------------------------------------------------

## Wind on the beam (from BEAM°, heading north) that gives `potential` knots.
func _wind_for(potential: float) -> WindField.Sample:
	if potential <= 0.0:
		return WindField.Sample.make(BEAM, 0.0)
	var low := 0.0
	var high := 60.0
	for i in 60:
		var mid := (low + high) / 2.0
		if profile.sail_speed_kn(mid, BEAM) < potential:
			low = mid
		else:
			high = mid
	return WindField.Sample.make(BEAM, high)


## Runs the controller every STEP seconds for `seconds` with potential(time).
## Returns the state and the times of mode changes.
func _run_controller(state: PropulsionState, potential: Callable, seconds: float, start := 0.0) -> Dictionary:
	var switches: Array = []
	var time := start
	while time <= start + seconds + 1e-6:
		var before := state.mode
		state = PropulsionController.evaluate(state, profile, time, 0.0, _wind_for(potential.call(time)))
		if state.mode != before and state.initialised and time > start:
			switches.append([time, state.mode])
		time += STEP
	return {"state": state, "switches": switches}


func _sailing_state(potential: float) -> PropulsionState:
	return PropulsionController.evaluate(PropulsionState.new(), profile, 0.0, 0.0, _wind_for(potential))


func _test_initial_choice() -> void:
	var good := _sailing_state(6.0)
	t.check(good.sails_set() and good.initialised, "leaving with a sailable wind: under sail")
	t.check(absf(good.speed_kn - 6.0) < 0.01, "under sail the speed is the potential sailing speed")
	var poor := _sailing_state(2.5)
	t.check(poor.is_motoring() and poor.engine_reason == PropulsionState.REASON_START, "leaving in light air: motoring")
	t.check_eq(poor.speed_kn, profile.engine_speed_kn, "motoring speed is the engine speed (5 kn)")
	t.check(absf(poor.potential_kn - 2.5) < 0.01, "the sailing potential is still evaluated while motoring")


func _test_sustained_poor_wind() -> void:
	var result := _run_controller(_sailing_state(7.0), func(time: float) -> float: return 7.0 if time < 3600.0 else 2.5, 6 * 3600.0)
	t.check_eq(result.switches.size(), 1, "a lasting drop to 2.5 kn starts the engine once")
	if result.switches.size() == 1:
		var after: float = result.switches[0][0] - 3600.0
		t.check(after >= 3600.0 and after <= 2.0 * 3600.0,
			"the engine starts only when the hour-average falls below 3.5 kn (after %s)" % Simulation.format_duration(after))
	t.check(result.state.is_motoring() and result.state.engine_reason == PropulsionState.REASON_POOR,
		"reason: insufficient sailing performance")


func _test_stall() -> void:
	var result := _run_controller(_sailing_state(7.0), func(time: float) -> float: return 7.0 if time < 3600.0 else 0.0, 3 * 3600.0)
	t.check(result.switches.size() == 1 and result.state.engine_reason == PropulsionState.REASON_STALL,
		"becalmed: the engine starts (reason: becalmed or head to wind)")
	if result.switches.size() == 1:
		var after: float = result.switches[0][0] - 3600.0
		t.check(after >= profile.stall_delay_s and after <= profile.stall_delay_s + 2.0 * STEP,
			"near-stall starts the engine promptly (after %s)" % Simulation.format_duration(after))


func _test_brief_dips() -> void:
	# 10 minutes of very light air and 30 minutes of marginal wind in a good breeze.
	var dips := func(time: float) -> float:
		if time >= 3600.0 and time < 4200.0:
			return 0.3
		if time >= 7200.0 and time < 9000.0:
			return 2.5
		return 7.0
	var result := _run_controller(_sailing_state(7.0), dips, 5 * 3600.0)
	t.check(result.switches.is_empty() and result.state.sails_set(), "short lulls do not start the engine")


func _test_engine_stops() -> void:
	var motoring: PropulsionState = _run_controller(_sailing_state(2.0), func(_time: float) -> float: return 2.0, 2 * 3600.0).state
	t.check(motoring.is_motoring(), "motoring in light air")
	var result := _run_controller(motoring, func(_time: float) -> float: return 7.5, 6 * 3600.0, 2 * 3600.0 + STEP)
	t.check_eq(result.switches.size(), 1, "a lasting good breeze stops the engine once")
	if result.switches.size() == 1:
		var after: float = result.switches[0][0] - 2 * 3600.0
		# I027 Tier 4: the threshold is the general 6 kn or, lower, the boat's
		# own speed under engine (never motor when the sails are as fast).
		var stop_kn := minf(profile.engine_stop_above_kn, profile.engine_speed_kn)
		t.check(after >= profile.engine_stop_confirm_s + 1800.0 and after <= 3.0 * 3600.0,
			"the engine stops only after the average has stayed above %.1f kn for a while (after %s)" % [stop_kn, Simulation.format_duration(after)])
	t.check(result.state.sails_set() and is_equal_approx(result.state.speed_kn, 7.5), "back under sail at the sailing speed")


func _test_hysteresis() -> void:
	var motoring := _sailing_state(2.0)
	var stay_engine := _run_controller(motoring, func(_time: float) -> float: return 5.0, 12 * 3600.0, STEP)
	t.check(stay_engine.switches.is_empty() and stay_engine.state.is_motoring(),
		"5 kn of sailing potential does not stop the engine (needs > 6 kn)")
	var stay_sail := _run_controller(_sailing_state(5.0), func(_time: float) -> float: return 5.0, 12 * 3600.0)
	t.check(stay_sail.switches.is_empty() and stay_sail.state.sails_set(),
		"5 kn of sailing potential does not start the engine (needs < 3.5 kn)")


func _test_no_cycling() -> void:
	# Wind alternating around both thresholds every 30 minutes for two days.
	var flip := func(time: float) -> float: return 3.0 if int(time / 1800.0) % 2 == 0 else 6.5
	var result := _run_controller(_sailing_state(4.0), flip, 48 * 3600.0)
	t.check(result.switches.size() <= 1, "no cycling when the wind hovers around the thresholds (%d switches in 48 h)" % result.switches.size())


func _test_course_change_resets() -> void:
	var state: PropulsionState = _run_controller(_sailing_state(7.0), func(_time: float) -> float: return 7.0, 3 * 3600.0).state
	var time := state.last_evaluation_time + STEP
	# New heading 90° away: the beam wind is now on the bow (head to wind).
	var turned := PropulsionController.evaluate(state, profile, time, 90.0 + 80.0, _wind_for(7.0))
	t.check(turned.average_potential_kn == turned.potential_kn, "a course change of more than 30° restarts the average from the new heading")
	t.check(turned.potential_kn < state.potential_kn, "the new heading's potential is used at once")
	var small := PropulsionController.evaluate(state, profile, time, 10.0, _wind_for(7.0))
	t.check(small.average_potential_kn != small.potential_kn or is_equal_approx(small.potential_kn, state.average_potential_kn),
		"a small course change keeps the running average")
	var forced := PropulsionController.evaluate(state, profile, time, 0.0, _wind_for(2.0), true)
	t.check(forced.is_motoring() and forced.engine_reason == PropulsionState.REASON_POOR,
		"after a change of course into poor wind the engine starts straight away")


func _test_spinnaker_state() -> void:
	var run := PropulsionController.evaluate(PropulsionState.new(), profile, 0.0, 0.0, WindField.Sample.make(150.0, 14.0))
	t.check(run.sails_set() and run.spinnaker, "sailing with the wind 150° off the bow: spinnaker set")
	var reach := PropulsionController.evaluate(PropulsionState.new(), profile, 0.0, 0.0, WindField.Sample.make(90.0, 14.0))
	t.check(reach.sails_set() and not reach.spinnaker, "on a beam reach: no spinnaker")
	var motoring := PropulsionController.evaluate(PropulsionState.new(), profile, 0.0, 0.0, WindField.Sample.make(150.0, 1.5))
	t.check(motoring.is_motoring() and not motoring.spinnaker, "never a spinnaker while motoring")
	t.check(run.true_wind_angle > 0.0 and run.describe().contains("spinnaker"), "description mentions the spinnaker")


# --- Simulation timeline -----------------------------------------------------------

## A deterministic changing wind: a good breeze, a long calm spell, then wind
## again. From the north-north-west, so it is sailable on the whole route from
## Lisbon to Gibraltar (out of the Tagus, south along the coast, east to the strait).
func _set_changing_wind(start: float) -> void:
	WindField.get_default().test_override = func(geo: Vector2, time: float) -> WindField.Sample:
		var hours := (time - start) / 3600.0
		var speed := 15.0 if hours < 9.0 else 20.0
		if hours > 3.0 and hours < 8.0:
			speed = 1.5
		elif hours >= 8.0 and hours < 9.0:
			speed = 4.0
		return WindField.Sample.make(340.0 + 15.0 * sin(hours * 0.3 + geo.x), speed)
	Simulation.invalidate_estimates()


func _start_voyage(from: StringName, to: StringName) -> void:
	GameSession.start_new_session()
	t.board(&"starling_33")  # timings written for the Wing 33's speeds
	if from != GameSession.START_LOCATION:
		var state := GameSession.get_state_snapshot()
		state.location_id = from
		state.vessel_position = PortCatalog.get_default().get_port(from).get_geo_position()
		GameSession.replace_state(state)
	GameSession.plan_route_to(to)
	GameSession.depart()


func _record(mode: StringName) -> void:
	changes.append([GameSession.get_game_time(), mode])


## Runs the same voyage with different step patterns; returns the end state.
func _run_pattern(pattern: StringName, hours: float) -> Dictionary:
	_set_changing_wind(SessionState.get_start_time())  # before departing: the departure decision uses it too
	_start_voyage(&"lisbon", &"gibraltar")
	changes.clear()
	GameSession.propulsion_changed.connect(_record)
	var total := hours * 3600.0
	match pattern:
		&"one_step":
			Simulation.advance(total)
		&"sleep":
			var slept := 0.0
			while slept < total - 1e-6:
				var result := Simulation.sleep(minf(8.0, (total - slept) / 3600.0))
				slept += result.elapsed_seconds
				if result.stopped_by == Simulation.STOP_ARRIVAL:
					break
		_:
			var scale := {&"1x": 1, &"5x": 5, &"20x": 20}[pattern] as int
			GameSession.set_time_scale(scale)
			var frame := 1.0 / 60.0 if scale == 1 else 1.0 / 30.0
			var guard := 0
			while GameSession.get_game_time() - SessionState.get_start_time() < total - 1e-6 and guard < 2000000:
				var left := total - (GameSession.get_game_time() - SessionState.get_start_time())
				Simulation.tick(minf(frame, left / (Simulation.game_seconds_per_real_second * scale)))
				GameSession.set_time_scale(scale)  # warnings drop back to 1×
				guard += 1
	GameSession.propulsion_changed.disconnect(_record)
	var propulsion := GameSession.get_propulsion()
	return {
		"progress": GameSession.get_voyage_progress_nm(), "time": GameSession.get_game_time(),
		"mode": propulsion.mode, "average": propulsion.average_potential_kn, "changes": changes.duplicate(true),
		"position": GameSession.get_vessel_position(),
	}


func _test_step_independence() -> void:
	var hours := 12.0
	var reference := _run_pattern(&"one_step", hours)
	var modes: Array = reference.changes.map(func(c: Array) -> StringName: return c[1])
	t.check(modes == [PropulsionState.MODE_ENGINE, PropulsionState.MODE_SAIL],
		"the test voyage sails, motors through the calm and sails again (%s)" % str(modes))
	for pattern: StringName in [&"1x", &"5x", &"20x", &"sleep"]:
		var other := _run_pattern(pattern, hours)
		var same_changes: bool = other.changes.size() == reference.changes.size()
		if same_changes:
			for i in other.changes.size():
				same_changes = same_changes and absf(other.changes[i][0] - reference.changes[i][0]) < 1e-3 \
					and other.changes[i][1] == reference.changes[i][1]
		t.check(absf(other.progress - reference.progress) < 1e-6 and absf(other.time - reference.time) < 1e-3 and other.mode == reference.mode,
			"%s gives the same position as one %d-hour step (%.6f vs %.6f nm)" % [pattern, hours, other.progress, reference.progress])
		t.check(same_changes, "%s switches sail/engine at the same game times" % pattern)


func _test_eta() -> void:
	t.set_wind(340.0, 14.0)
	_start_voyage(&"lisbon", &"gibraltar")
	var start := GameSession.get_game_time()
	var estimate := Simulation.get_eta()
	var arrived_at := [0.0]
	var on_arrival := func(_port: StringName) -> void: arrived_at[0] = GameSession.get_game_time()
	Simulation.arrived.connect(on_arrival)
	Simulation.advance(200.0 * 3600.0)
	Simulation.arrived.disconnect(on_arrival)
	t.check_eq(GameSession.get_location_id(), &"gibraltar", "the wind-driven voyage arrives")
	var actual: float = arrived_at[0]
	var error := absf(estimate - actual) / (actual - start)
	t.check(error < 0.05, "the wind-aware ETA is close to the actual arrival (%.1f%% off)" % (error * 100.0))

	# A calm voyage: the estimate assumes motoring at 5 kn.
	t.use_calm_wind()
	_start_voyage(&"copenhagen", &"kiel")
	var calm_eta := Simulation.get_eta() - GameSession.get_game_time()
	var expected := GameSession.get_voyage_total_nm() / profile.engine_speed_kn * 3600.0
	t.check(absf(calm_eta - expected) < 60.0, "in a calm the ETA is the motoring time at 5 kn")


func _test_warnings_with_wind() -> void:
	t.set_wind(200.0, 14.0)
	_start_voyage(&"copenhagen", &"kiel")
	var received: Array[Dictionary] = []
	var on_warning := func(w: Dictionary) -> void: received.append(w)
	Simulation.weather_warning.connect(on_warning)
	var result := Simulation.sleep(48.0)
	Simulation.weather_warning.disconnect(on_warning)
	t.check(result.stopped_by == Simulation.STOP_WARNING and received.size() == 1, "weather warnings still wake the crew while sailing")
	if not received.is_empty():
		var w := received[0]
		var speed := GameSession.get_vessel_speed_kn()
		t.check(w.hours <= Simulation.WARNING_HORIZON_HOURS + 0.01 and w.distance_nm > 0.0,
			"the warning looks ahead in sailing time (%.1f kn now, %.1f h / %.1f nm ahead)" % [speed, w.hours, w.distance_nm])


func _test_course_change_at_sea() -> void:
	t.set_wind(200.0, 14.0)
	_start_voyage(&"copenhagen", &"kiel")
	Simulation.advance(3.0 * 3600.0)
	var before := GameSession.get_propulsion()
	var error := GameSession.change_course(&"gothenburg", [] as Array[Vector2])
	var after := GameSession.get_propulsion()
	t.check(error.is_empty() and after.last_evaluation_time == GameSession.get_game_time(),
		"a change of course re-evaluates the propulsion at once")
	t.check(absf(after.heading_deg - Simulation.get_current_heading()) < 1e-6 and after.heading_deg != before.heading_deg,
		"the new heading is used (%.0f° -> %.0f°)" % [before.heading_deg, after.heading_deg])


func _test_save_and_load() -> void:
	_set_changing_wind(SessionState.get_start_time())
	_start_voyage(&"lisbon", &"gibraltar")
	Simulation.advance(4.0 * 3600.0)  # in the calm, motoring
	t.check(GameSession.is_motoring(), "motoring in the calm before saving")
	var saved := GameSession.get_state_snapshot()
	var data := JSON.parse_string(JSON.stringify({"s": saved.to_dict()}, "", true, true)) as Dictionary
	Simulation.advance(6.0 * 3600.0)
	var continued := GameSession.get_state_snapshot().to_dict()

	var errors: Array[String] = []
	var loaded := SessionState.from_dict(data.s, errors)
	t.check(loaded != null and errors.is_empty(), "the propulsion state saves and validates: %s" % str(errors))
	if loaded == null:
		return
	t.check(loaded.propulsion.is_motoring() and loaded.propulsion.initialised, "the saved mode is restored (motoring)")
	t.check(is_equal_approx(loaded.propulsion.average_potential_kn, saved.propulsion.average_potential_kn)
		and is_equal_approx(loaded.propulsion.mode_seconds, saved.propulsion.mode_seconds), "the controller's averages and timers are restored")
	t.check_eq(loaded.wind_seed, saved.wind_seed, "the wind seed is saved")
	GameSession.replace_state(loaded)
	t.check(GameSession.is_motoring(), "loading does not re-decide the mode")
	Simulation.advance(6.0 * 3600.0)
	var resumed := GameSession.get_state_snapshot().to_dict()
	t.check(absf(resumed.navigation.voyage.progress_nm - continued.navigation.voyage.progress_nm) < 1e-6
		and resumed.vessel.propulsion.mode == continued.vessel.propulsion.mode,
		"a loaded voyage continues exactly as if it had never been saved")

	var bad: Dictionary = data.s.duplicate(true)
	bad.vessel.propulsion.mode = "oars"
	errors.clear()
	t.check(SessionState.from_dict(bad, errors) == null, "an invalid propulsion mode is rejected")
	bad = data.s.duplicate(true)
	bad.vessel.propulsion.speed_kn = -3.0
	errors.clear()
	t.check(SessionState.from_dict(bad, errors) == null, "a negative speed is rejected")


func _test_migration_from_v2() -> void:
	t.set_wind(200.0, 14.0)
	_start_voyage(&"copenhagen", &"kiel")
	Simulation.advance(2.0 * 3600.0)
	var session := GameSession.get_state_snapshot().to_dict()
	session.erase("wind")
	session.vessel.erase("propulsion")
	session.vessel["speed_kn"] = 5.0
	var v2 := {"format": "next_harbor_save", "version": 2, "game_version": "0.2.0",
		"saved_at_unix": 1790000000.0, "saved_at_utc": "2026-09-21T12:53:20Z", "session": session}
	var path := SaveManager.save_dir.path_join("slot_3.json")
	DirAccess.make_dir_recursive_absolute(SaveManager.save_dir)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(v2, "", true, true))
	file.close()
	var loaded := SaveManager.load_from_slot(3)
	t.check(loaded.is_ok(), "an Iteration 002 save (v2) mid-voyage loads: %s" % loaded.error)
	if not loaded.is_ok():
		return
	t.check(not loaded.state.propulsion.initialised and loaded.state.wind_seed == 1, "migration adds the wind seed and a fresh controller")
	var progress: float = session.navigation.voyage.progress_nm
	GameSession.replace_state(loaded.state)
	t.check(GameSession.get_propulsion().initialised and GameSession.get_game_time() == session.clock.game_time,
		"the migrated voyage gets a propulsion decision at once, and no time passes on loading")
	t.check(absf(GameSession.get_voyage_progress_nm() - progress) < 1e-9, "no offline travel: the boat is where it was saved")
	DirAccess.remove_absolute(path)
