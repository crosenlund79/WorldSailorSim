extends RefCounted
## Iteration 18 (TRIM): sail trim.
##   - the best setting follows the wind angle (sheeted in close-hauled, eased
##     running) and a strong wind;
##   - the effect is modest (+6 % at best, -10 % at worst; the crew's trim is
##     the sailing model exactly), applies to sailing only, never to the
##     choice between sail and engine, and does not stack;
##   - fast time sails the same with a hand trim (big and small steps);
##     stores and wear follow time, not trim;
##   - the setting is kept across course changes and saves (old saves: the
##     crew trims), its effect worked out from the wind of the moment;
##   - T and the action wheel open the trim panel underway; the sailing panel
##     says how the sails are trimmed.

const APP_SCENE := preload("res://src/app/app.tscn")

var t: Node
var app: Node


func run(runner: Node) -> void:
	t = runner
	_test_rules()
	Simulation.auto_advance = false
	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	app.start_new_game()
	await _settle()
	_test_effect_underway()
	_test_fast_time_equivalence()
	_test_persistence()
	await _test_panel()
	Simulation.auto_advance = true
	app.queue_free()
	await t.frames(2)
	GameSession.end_session()
	t.use_calm_wind()


func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)


func _test_rules() -> void:
	t.check(SailTrim.best(45.0, 12.0) > 0.5 and absf(SailTrim.best(95.0, 12.0)) < 0.1 and SailTrim.best(170.0, 12.0) < -0.5,
		"[trim] best: sheeted in close-hauled (%.2f), middle on a beam reach (%.2f), eased on a run (%.2f)" % [
			SailTrim.best(45.0, 12.0), SailTrim.best(95.0, 12.0), SailTrim.best(170.0, 12.0)])
	t.check(SailTrim.best(-60.0, 12.0) == SailTrim.best(60.0, 12.0), "[trim] the same on either tack")
	t.check(SailTrim.best(90.0, 28.0) > SailTrim.best(90.0, 12.0), "[trim] in a strong wind a little flatter (tighter)")
	t.check_eq(SailTrim.factor(true, 0.7, 90.0, 12.0), 1.0, "[trim] left to the crew: the sailing model exactly")
	var lowest := INF
	var highest := -INF
	for angle in range(30, 181, 10):
		for k in 41:
			var f := SailTrim.factor(false, -1.0 + k * 0.05, float(angle), 14.0)
			lowest = minf(lowest, f)
			highest = maxf(highest, f)
	t.check(is_equal_approx(highest, 1.0 + SailTrim.BONUS) and is_equal_approx(lowest, 1.0 - SailTrim.PENALTY),
		"[trim] modest: from %+.0f %% to %+.0f %%" % [(lowest - 1.0) * 100.0, (highest - 1.0) * 100.0])
	var best := SailTrim.best(90.0, 12.0)
	t.check(SailTrim.feedback(false, best, 90.0, 12.0) == "Well trimmed" and SailTrim.feedback(false, best + 0.5, 90.0, 12.0) == "Too tight"
		and SailTrim.feedback(false, best - 0.5, 90.0, 12.0) == "Too loose" and SailTrim.feedback(true, 0.0, 90.0, 12.0) == "Trimmed by the crew",
		"[trim] plain words: Well trimmed, Too tight, Too loose, Trimmed by the crew")


## Sails 6 hours from the same start with the crew's, the best and a poor trim.
## `offset`: a hand trim this far from the best (re-trimmed every 5 minutes,
## as the course and wind change); NAN: the crew trims.
func _sail(offset: float, hours := 6.0) -> Dictionary:
	GameSession.replace_state(_start)
	Simulation.evaluate_propulsion()
	var modes := []
	var food := GameSession.get_provisions().food_days
	var condition := GameSession.get_condition()
	for i in int(hours * 12):
		var p := GameSession.get_propulsion()
		if is_nan(offset):
			GameSession.set_sail_trim(true, 0.0)
		else:
			GameSession.set_sail_trim(false, SailTrim.best(p.true_wind_angle, p.wind_speed_kn) + offset)
		Simulation.advance(300.0)
		modes.append(GameSession.get_propulsion().mode)
	return {"nm": GameSession.get_voyage_progress_nm(), "modes": modes, "food": food - GameSession.get_provisions().food_days,
		"wear": condition - GameSession.get_condition(), "potential": GameSession.get_propulsion().potential_kn}


var _start: SessionState


func _test_effect_underway() -> void:
	t.set_wind(270.0, 14.0)
	GameSession.plan_route_to(&"las_palmas")
	t.check_eq(GameSession.depart(), "", "(setup) underway")
	Simulation.advance(600.0)
	_start = GameSession.get_state_snapshot()
	var propulsion := GameSession.get_propulsion()
	var angle := propulsion.true_wind_angle
	var best := SailTrim.best(angle, propulsion.wind_speed_kn)
	var crew := _sail(NAN)
	var good := _sail(0.0)
	var poor := _sail(0.9 if best < 0.0 else -0.9)
	var gain := float(good.nm) / float(crew.nm) - 1.0
	var loss := float(poor.nm) / float(crew.nm) - 1.0
	t.check(gain > 0.02 and gain <= SailTrim.BONUS + 0.005, "[effect] kept well trimmed by hand: %+.1f %% further in 6 h (%.1f vs %.1f nm)" % [gain * 100.0, good.nm, crew.nm])
	t.check(loss < -0.04 and loss >= -SailTrim.PENALTY - 0.005, "[effect] badly trimmed: %+.1f %% (modest, not stranded)" % (loss * 100.0))
	t.check(good.modes == crew.modes and poor.modes == crew.modes, "[effect] trim never starts or stops the engine")
	t.check(is_equal_approx(float(good.potential), float(crew.potential)), "[effect] the sailing model's potential is untouched")
	t.check(is_equal_approx(float(good.food), float(crew.food)) and is_equal_approx(float(poor.wear), float(crew.wear)),
		"[effect] stores and wear follow the time sailed, not the trim")
	# No stacking: setting the same trim again and again changes nothing.
	GameSession.replace_state(_start)
	Simulation.evaluate_propulsion()
	GameSession.set_sail_trim(false, best)
	var once := GameSession.get_propulsion().speed_kn
	for i in 20:
		GameSession.set_sail_trim(false, best)
	t.check(is_equal_approx(GameSession.get_propulsion().speed_kn, once) and once <= GameSession.get_propulsion().potential_kn * (1.0 + SailTrim.BONUS) + 1e-6,
		"[effect] no stacking: twenty times the same trim is the same speed (%.2f kn)" % once)
	# Under engine trim does nothing.
	GameSession.replace_state(_start)
	t.set_wind(270.0, 1.0)
	Simulation.evaluate_propulsion(true, true)
	for i in 30:
		Simulation.advance(600.0)
	var motoring := GameSession.get_propulsion()
	if t.check(motoring.is_motoring(), "(setup) in a calm the engine runs"):
		GameSession.set_sail_trim(false, -1.0)
		t.check(is_equal_approx(GameSession.get_propulsion().speed_kn, motoring.speed_kn), "[effect] under engine the trim makes no difference")
	t.set_wind(270.0, 14.0)
	GameSession.replace_state(_start)


## The same voyage with a hand trim in big and in small steps.
func _test_fast_time_equivalence() -> void:
	var results := []
	for step in [5.0, 3600.0]:
		GameSession.replace_state(_start)
		GameSession.set_sail_trim(false, 0.4)
		var elapsed := 0.0
		while elapsed < 12.0 * 3600.0:
			Simulation.advance(step)
			elapsed += step
		results.append([GameSession.get_voyage_progress_nm(), GameSession.get_provisions().food_days, GameSession.get_condition()])
	t.check(absf(float(results[0][0]) - float(results[1][0])) < 1e-6 and absf(float(results[0][1]) - float(results[1][1])) < 1e-9,
		"[fast] a hand trim sails the same in 5 s and in 1 h steps (%.4f vs %.4f nm)" % [results[0][0], results[1][0]])
	GameSession.replace_state(_start)


func _test_persistence() -> void:
	GameSession.replace_state(_start)
	t.check(GameSession.get_last_location_recovery().is_empty(),
		"[save] a voyage ten minutes out of Copenhagen loads as it was (no \"chart has been updated\") (%s)" % GameSession.get_last_location_recovery())
	GameSession.set_sail_trim(false, -0.35)
	var data := GameSession.get_state_snapshot().to_dict()
	var errors: Array[String] = []
	var restored := SessionState.from_dict(JSON.parse_string(JSON.stringify(data)), errors)
	t.check(restored != null and not restored.trim_auto and is_equal_approx(restored.trim_value, -0.35), "[save] the hand trim is saved and loaded")
	data.vessel.erase("sail_trim")
	var old := SessionState.from_dict(JSON.parse_string(JSON.stringify(data)), errors)
	t.check(old != null and old.trim_auto, "[save] a 0.104a save (no trim): the crew trims")
	# Kept across a change of course; its effect follows the new wind angle.
	var before := SailTrim.feedback(false, -0.35, GameSession.get_propulsion().true_wind_angle, GameSession.get_propulsion().wind_speed_kn)
	t.set_wind(GameSession.get_propulsion().heading_deg, 14.0)  # now dead ahead... close-hauled at best
	Simulation.evaluate_propulsion(true, true)
	var trim := GameSession.get_sail_trim()
	t.check(not trim.auto and is_equal_approx(float(trim.value), -0.35), "[keep] the setting stays when the wind or course changes")
	t.set_wind(270.0, 14.0)
	GameSession.replace_state(_start)
	t.check(before != "", "(setup) %s" % before)


func _test_panel() -> void:
	GameSession.replace_state(_start)
	GameSession.enter_boat_area(SessionState.AREA_EXTERIOR, &"start")
	app._show_current_boat_area()
	await _settle()
	GameSession.set_sail_trim(true, 0.0)
	Simulation.evaluate_propulsion()
	await t.frames(2)
	app.hud.instrument_cluster.refresh()
	var row: String = app.hud.instrument_cluster.get_value("trim")
	t.check(row.contains("crew") and row.contains("T"), "[panel] the instruments read the trim and its key (%s)" % row)
	var wheel: Array = app.get_wheel_actions().map(func(a: Dictionary) -> StringName: return a.id)
	t.check(&"sail_trim" in wheel, "[panel] the action wheel at the helm offers \"Trim the sails\"")
	await t.press_action(&"sail_trim")
	await t.frames(2)
	var panel := app.modals.get_top() as SailTrimPanel
	if not t.check(panel != null, "[panel] T opens the sail trim"):
		return
	var propulsion := GameSession.get_propulsion()
	var best := SailTrim.best(propulsion.true_wind_angle, propulsion.wind_speed_kn)
	(panel.find_child("Trim", true, false) as HSlider).value = best
	await t.frames(1)
	t.check(not GameSession.get_sail_trim().auto and panel.get_feedback_text().begins_with("Well trimmed"), "[panel] moving the slider trims by hand (%s)" % panel.get_feedback_text())
	await t.screenshot("18_sail_trim_well")
	var slow := GameSession.get_propulsion().speed_kn
	await t.press_action(&"move_left")
	for i in 14:
		await t.press_action(&"move_left")
	await t.frames(1)
	t.check(GameSession.get_sail_trim().value < best - 0.6 and panel.get_feedback_text().begins_with("Too loose") and GameSession.get_propulsion().speed_kn < slow,
		"[panel] A eases the sheets: \"Too loose\" and slower at once (%s)" % panel.get_feedback_text())
	await t.screenshot("18_sail_trim_too_loose")
	await t.press_action(&"ui_accept")
	await t.frames(1)
	t.check(GameSession.get_sail_trim().auto, "[panel] Space hands it back to the crew")
	await t.press_action(&"sail_trim")
	await t.frames(2)
	t.check(app.modals.is_empty(), "[panel] T closes it")
	GameSession.replace_state(_start)
