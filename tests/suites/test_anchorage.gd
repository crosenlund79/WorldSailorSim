extends RefCounted
## Iteration 18 (ANCH-1 to ANCH-8): anchorage waypoints.
##   - on the working chart a waypoint can be marked as an anchorage (button
##     or M), shown with an anchor; a spot the anchoring rule does not allow
##     (land, or too far from the coast) is not marked: the reason is given
##     and the nearest suitable spot offered; a first-use hint;
##   - the flag belongs to the route's waypoints: applied, saved, kept when
##     the course is changed at sea, across the Date Line;
##   - arriving: the boat stops at the spot (not anchored), Long Passage
##     stops, the captain is asked once ("We've arrived at our anchorage.
##     Ready to drop anchor?"); time passes without moving; no repeat after
##     loading;
##   - anchoring is the normal action with its normal checks (it can fail);
##     "Sail on" or weighing anchor continues the rest of the course, which
##     is unchanged; the same anchorage never stops the boat twice.

const APP_SCENE := preload("res://src/app/app.tscn")

var t: Node
var app: Node
var spot := Vector2.INF


func run(runner: Node) -> void:
	t = runner
	Simulation.auto_advance = false
	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	app.start_new_game()
	await _settle()
	t.set_wind(200.0, 10.0)
	await _test_marking()
	await _test_arrival_and_prompt()
	await _test_anchor_and_resume()
	await _test_sail_on_and_change_course()
	_test_date_line_and_old_saves()
	Simulation.auto_advance = true
	app.queue_free()
	await t.frames(2)
	GameSession.end_session()
	t.use_calm_wind()


func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)


func _open_chart() -> WorldMap:
	app.modals.clear()
	app.open_chart()
	await t.wait_until(func() -> bool: return app.router.current_screen is WorldMap and not app.router.is_busy(), 10.0)
	await t.frames(2)
	return app.router.current_screen as WorldMap


func _close_chart() -> void:
	app.close_chart()
	await _settle()


func _moor(port_id: StringName) -> void:
	var state := GameSession.get_state_snapshot()
	state.location_id = port_id
	state.vessel_status = SessionState.STATUS_MOORED
	state.vessel_position = PortCatalog.get_default().get_port(port_id).get_geo_position()
	state.voyage = null
	state.planned_route = null
	state.anchor.active = false
	GameSession.replace_state(state)


# --- Marking on the chart ------------------------------------------------------------

func _test_marking() -> void:
	var world := await _open_chart()
	if not t.check(world != null, "(setup) the chart is open"):
		return
	world.set_wind_shown(false)
	world.plot_course_to(&"gothenburg")
	await t.frames(1)
	t.check(world.get_draft_route() != null, "(setup) a course to Gothenburg")
	# A point on the course well away from any coast: too deep for the normal
	# anchor (0.105b: depth, not distance, decides; 5 nm out is deep here).
	var offshore := Vector2.INF
	var path := world.get_draft_route().path
	for i in range(path.size() - 1):
		for f in [0.25, 0.5, 0.75]:
			var p: Vector2 = path[i].lerp(path[i + 1], f)
			if offshore == Vector2.INF and SeaRouter.get_default().is_point_navigable(p) and float(GameSession.anchorage_spot(p).land_nm) >= 5.0 \
					and not GameSession.anchorage_spot(p).ok:
				offshore = p
	if not t.check(offshore != Vector2.INF, "(setup) open water on the course, far from land"):
		return
	var index := world.insert_waypoint(world.get_draft_legs().size() - 1, offshore)
	t.check(world.get_course_status_text().contains("mark it as an anchorage"), "[hint] the first waypoint brings the anchorage hint (%s)" % world.get_course_status_text())
	var reason := world.toggle_anchorage(index)
	t.check(not world.is_anchorage(index) and reason.contains("too deep for the normal anchor"), "[mark] far offshore is refused for the normal anchor: %s" % reason)
	t.check(world.get_anchorage_suggestion() != Vector2.INF and GameSession.anchorage_spot(world.get_anchorage_suggestion()).ok,
		"[mark] and the nearest suitable spot is offered (%s)" % GeoMath.format_position(world.get_anchorage_suggestion()))
	world.use_anchorage_suggestion()
	await t.frames(1)
	spot = world.get_draft_waypoints()[index]
	t.check(world.is_anchorage(index) and GameSession.anchorage_spot(spot).ok and world.get_draft_route() != null,
		"[mark] moved there and marked: an anchorage within %.1f nm of land, the course still found" % AnchorSite.MAX_LAND_NM)
	var map := world.get_map_view()
	t.check(map.anchorages.size() == map.waypoints.size() and map.anchorages[index], "[chart] the chart draws it as an anchorage")
	map.center_on_geo(spot, 600.0 / map.units_per_degree)
	await t.frames(2)
	await t.screenshot("18_anchorage_waypoint")
	# Land is refused.
	var land_index := world.insert_waypoint(0, Vector2(12.45, 55.75))
	var land_reason := world.toggle_anchorage(land_index)
	t.check(not world.is_anchorage(land_index) and land_reason.contains("Land"), "[mark] on land is refused: %s" % land_reason)
	world.remove_waypoint(land_index)
	index = world.get_draft_waypoints().find(spot)
	# M toggles the selected waypoint; the hint is not repeated.
	world._select_waypoint(index)
	await t.press_key(KEY_M)
	t.check(not world.is_anchorage(index), "[mark] M unmarks the selected waypoint")
	await t.press_key(KEY_M)
	t.check(world.is_anchorage(index), "[mark] and M marks it again")
	world.insert_waypoint(0, Vector2(12.7, 55.9))
	t.check(not world.get_course_status_text().contains("mark it as an anchorage"), "[hint] the hint comes once only")
	world.remove_waypoint(0)
	index = world.get_draft_waypoints().find(spot)
	t.check_eq(world.apply_course(), "", "[apply] the course with its anchorage is set")
	var planned := GameSession.get_planned_route()
	t.check(planned != null and planned.is_anchorage(planned.waypoints.find(spot)), "[apply] the planned route knows the anchorage")
	# Saved and loaded with the route.
	var errors: Array[String] = []
	var restored := SessionState.from_dict(JSON.parse_string(JSON.stringify(GameSession.get_state_snapshot().to_dict())), errors)
	t.check(restored != null and restored.planned_route.is_anchorage(restored.planned_route.waypoints.find(spot)),
		"[save] the anchorage is saved with the planned route")
	await _close_chart()


# --- Arriving ----------------------------------------------------------------------

func _test_arrival_and_prompt() -> void:
	t.check_eq(GameSession.depart(), "", "(setup) depart Copenhagen for Gothenburg")
	var route_before := GameSession.get_voyage().route.to_dict()
	# Long Passage toward it: it stops for the anchorage.
	t.check_eq(Simulation.start_passage(Simulation.PASSAGE_RATES[1]), "", "(setup) Long Passage time")
	var reasons := []
	var stop := func(reason: StringName, _text: String) -> void: reasons.append(reason)
	Simulation.passage_interrupted.connect(stop)
	var guard := 0
	while not GameSession.is_holding_at_anchorage() and GameSession.is_underway() and guard < 20000:
		if not Simulation.is_passage_running():
			Simulation.start_passage(Simulation.PASSAGE_RATES[1])
		Simulation._passage_tick(0.05)
		guard += 1
	Simulation.passage_interrupted.disconnect(stop)
	t.check(GameSession.is_holding_at_anchorage(), "[arrive] the boat reaches the anchorage and stops there")
	t.check(Simulation.STOP_ANCHORAGE in reasons and not Simulation.is_passage_running(), "[arrive] Long Passage time stops for it (%s)" % [reasons])
	t.check(GameSession.get_vessel_position().distance_to(spot) < 1e-3, "[arrive] exactly at the chosen spot (%s)" % GeoMath.format_position(GameSession.get_vessel_position()))
	t.check(not GameSession.is_anchored() and GameSession.get_vessel_speed_kn() == 0.0, "[arrive] stopped, but the anchor is not set by itself")
	t.check(Simulation.start_passage(Simulation.PASSAGE_RATES[0]) != "", "[arrive] Long Passage cannot start while waiting at the anchorage")
	# The prompt, once.
	GameSession.enter_boat_area(SessionState.AREA_EXTERIOR, &"start")
	app._show_current_boat_area()
	await _settle()
	await t.frames(3)
	var prompt := app.modals.get_top() as AnchoragePrompt
	t.check(prompt != null and (prompt.find_child("Question", true, false) as Label).text == "We've arrived at our anchorage. Ready to drop anchor?",
		"[prompt] \"We've arrived at our anchorage. Ready to drop anchor?\"")
	await t.screenshot("18_anchorage_arrival_prompt")
	if prompt:
		(prompt.find_child("WaitButton", true, false) as Button).pressed.emit()
	await t.frames(2)
	var progress := GameSession.get_voyage_progress_nm()
	Simulation.advance(2.0 * 3600.0)
	await t.frames(3)
	t.check(GameSession.is_holding_at_anchorage() and is_equal_approx(GameSession.get_voyage_progress_nm(), progress),
		"[wait] \"Not yet\": two hours later the boat still waits there")
	t.check(app.modals.is_empty() and not app.is_anchorage_prompt_due(), "[wait] and the question is not asked again")
	var wheel: Array = app.get_wheel_actions().map(func(a: Dictionary) -> StringName: return a.id)
	t.check(&"anchor" in wheel and &"sail_on" in wheel, "[wait] the action wheel offers the anchor and \"Sail on\" (%s)" % [wheel])
	t.check(app.hud.instrument_cluster.get_value("speed").contains("anchorage") and app.hud.instrument_cluster.get_status_text().contains("sail on"),
		"[wait] the instruments say so (%s)" % app.hud.instrument_cluster.get_status_text())
	t.check(GameSession.get_fishing_mode() == FishingState.MODE_STATIONARY, "[wait] waiting there, one fishes from a still boat")
	# Save while waiting, load: still waiting, no second prompt.
	t.check_eq(SaveManager.save_to_slot(3, GameSession.get_state_snapshot()), OK, "(setup) saved at the anchorage")
	app.load_slot(3)
	await _settle()
	await t.frames(3)
	t.check(GameSession.is_holding_at_anchorage() and GameSession.get_vessel_position().distance_to(spot) < 1e-3 and not app.is_anchorage_prompt_due()
		and not (app.modals.get_top() is AnchoragePrompt), "[save] loaded at the anchorage: still waiting, asked no second time")
	t.check(JSON.stringify(GameSession.get_voyage().route.to_dict()) == JSON.stringify(route_before), "[save] the course is as it was")
	SaveManager.delete_slot(3)


func _test_anchor_and_resume() -> void:
	var voyage := GameSession.get_voyage()
	var index := voyage.holding_at
	# Too much wind: anchoring fails with its usual reason; the boat keeps waiting.
	t.set_wind(200.0, 40.0)
	var refused := GameSession.drop_anchor(5, 0.9)
	t.check(refused.error != "" and GameSession.is_holding_at_anchorage() and not GameSession.is_anchored(),
		"[anchor] the normal checks apply: %s" % refused.error)
	t.set_wind(200.0, 10.0)
	var dropped := GameSession.drop_anchor(5, 0.9)
	t.check(dropped.error == "" and GameSession.is_anchored() and not GameSession.is_holding_at_anchorage(),
		"[anchor] the anchor goes down the usual way: %s" % AnchorSite.holding_text(dropped.holding))
	t.check(index in GameSession.get_voyage().anchorages_done, "[anchor] that anchorage is done")
	var progress := GameSession.get_voyage_progress_nm()
	Simulation.advance(3.0 * 3600.0)
	t.check(is_equal_approx(GameSession.get_voyage_progress_nm(), progress), "[anchor] at anchor the course does not go on by itself")
	# Save at anchor, load.
	t.check_eq(SaveManager.save_to_slot(3, GameSession.get_state_snapshot()), OK, "(setup) saved at anchor")
	app.load_slot(3)
	await _settle()
	t.check(GameSession.is_anchored() and index in GameSession.get_voyage().anchorages_done, "[save] loaded at anchor at the anchorage")
	SaveManager.delete_slot(3)
	var remaining := GameSession.get_voyage().get_remaining_path()
	t.check_eq(GameSession.raise_anchor(), "", "[resume] anchor up")
	t.check(GameSession.get_voyage().get_remaining_path() == remaining, "[resume] the rest of the course is unchanged")
	var arrived := false
	var stops := 0
	for i in 400:
		if Simulation.advance(1800.0, true).stopped_by == Simulation.STOP_ANCHORAGE:
			stops += 1
		if not GameSession.is_underway():
			arrived = GameSession.get_location_id() == &"gothenburg"
			break
	t.check(arrived and stops == 0, "[resume] the voyage continues to Gothenburg, never stopping at the same anchorage again (%d)" % stops)


func _test_sail_on_and_change_course() -> void:
	_moor(&"copenhagen")
	var router := SeaRouter.get_default()
	var result := router.plan_route(&"copenhagen", PortCatalog.get_default().get_port(&"copenhagen").get_geo_position(), [spot] as Array[Vector2], &"gothenburg")
	if not t.check(result.is_ok(), "(setup) a course through the anchorage"):
		return
	result.route.anchorages = [true] as Array[bool]
	t.check_eq(GameSession.set_planned_route(result.route), "", "(setup) planned")
	t.check_eq(GameSession.depart(), "", "(setup) departed")
	for i in 400:
		Simulation.advance(1800.0, true)
		if GameSession.is_holding_at_anchorage():
			break
	t.check(GameSession.is_holding_at_anchorage(), "(setup) waiting at the anchorage again")
	t.check_eq(GameSession.sail_on_from_anchorage(), "", "[sail on] \"Sail on\": no anchoring")
	var before := GameSession.get_voyage_progress_nm()
	Simulation.advance(1800.0, true)
	t.check(GameSession.get_voyage_progress_nm() > before and not GameSession.is_holding_at_anchorage(), "[sail on] the boat sails on along the course")
	# A change of course at sea keeps flags for the waypoints given.
	var ahead := GameSession.nearest_anchorage_spot(Vector2(11.75, 57.6))
	if t.check(ahead != Vector2.INF, "(setup) a spot near the Swedish coast"):
		t.check_eq(GameSession.change_course(&"gothenburg", [ahead] as Array[Vector2], [true] as Array[bool]), "", "[change] a new course with an anchorage, at sea")
		t.check(GameSession.get_next_anchorage().get("index", -1) == 0, "[change] the new anchorage is the next stop (%s)" % [GameSession.get_next_anchorage()])
	GameSession.change_course(&"gothenburg", [] as Array[Vector2])
	t.check(GameSession.get_next_anchorage().is_empty(), "[change] a course without anchorages has none")


func _test_date_line_and_old_saves() -> void:
	# Abroad the world chart is coarse (cells of about 5 nm): no spot there is
	# known to be within reach of the bottom, so none is offered - and the
	# captain is told why, never routed somewhere unsafe.
	# 0.105b: this used to check the I018 limitation (no anchorage on the coarse
	# ocean chart); the Captain has made worldwide anchoring a requirement, so
	# now a suitable anchorage is found off New Zealand.
	var near_nz := GameSession.nearest_anchorage_spot(Vector2(174.3, -35.3), 12.0)
	var abroad := GameSession.anchorage_spot(near_nz) if near_nz != Vector2.INF else {"ok": false, "reason": "none found"}
	t.check(abroad.ok, "[abroad] off New Zealand an anchorage for the normal anchor is found (%s: %s)" % [GeoMath.format_position(near_nz) if near_nz != Vector2.INF else "-", abroad.reason])
	_moor(&"papeete")
	var router := SeaRouter.get_default()
	var result := router.plan_route(&"papeete", PortCatalog.get_default().get_port(&"papeete").get_geo_position(),
		[Vector2(-170.0, -24.0), Vector2(179.9, -26.0)] as Array[Vector2], &"auckland")
	if t.check(result.is_ok(), "[date line] a course across the Date Line with two waypoints plots (%s)" % result.error):
		result.route.anchorages = [false, true] as Array[bool]
		var errors: Array[String] = []
		var copy := PlannedRoute.from_dict(JSON.parse_string(JSON.stringify(result.route.to_dict())), PortCatalog.get_default(), errors)
		t.check(copy != null and not copy.is_anchorage(0) and copy.is_anchorage(1), "[date line] the anchorage flag stays with its waypoint across the Date Line")
	# A 0.104a voyage (no anchorage fields) loads with none.
	_moor(&"copenhagen")
	GameSession.plan_route_to(&"gothenburg")
	GameSession.depart()
	var data := GameSession.get_state_snapshot().to_dict()
	data.navigation.voyage.erase("holding_at")
	data.navigation.voyage.erase("anchorages_done")
	data.navigation.voyage.route.erase("anchorages")
	var errors2: Array[String] = []
	var old := SessionState.from_dict(JSON.parse_string(JSON.stringify(data)), errors2)
	t.check(old != null and old.voyage.holding_at == -1 and old.voyage.next_anchorage().is_empty(), "[save] a 0.104a voyage loads with no anchorages (%s)" % [errors2])
