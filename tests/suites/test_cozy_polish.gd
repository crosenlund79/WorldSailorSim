extends RefCounted
## Injection 1, Cozy Polish: navigation and quality of life.
##   - canals: Kiel, Suez (with Bab-el-Mandeb), Panama unchanged, the Baltic
##     around Stockholm; planned, validated, sailed and saved mid-canal;
##   - the chart's smallest zoom stays on its data;
##   - the Palermo-Limassol stray waypoint: a click does not add one, a
##     waypoint on land moves to water or goes, replanning leaves nothing stale;
##   - floating things at sea pass the boat astern, at any heading;
##   - the Q menu's labels and live check marks;
##   - coffee and the hat in hand, the cup holders on all four boats;
##   - the sleep duration remembered; visited-harbour pins; compact panels;
##     the loading screen; saves with and without a coffee mug.

const APP_SCENE := preload("res://src/app/app.tscn")

var t: Node
var app: Node
var router: SeaRouter
var catalog: PortCatalog


func run(runner: Node) -> void:
	t = runner
	router = SeaRouter.get_default()
	catalog = PortCatalog.get_default()
	Simulation.auto_advance = false
	_test_canal_routes()
	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	app.start_new_game()
	await _settle()
	await _test_canal_voyage()
	await _test_chart_zoom()
	await _test_canal_charts()
	await _test_route_replanning()
	await _test_debris()
	await _test_wheel()
	await _test_coffee_all_boats()
	await _test_sleep_memory()
	await _test_pins()
	await _test_compact_ui()
	await _test_loading_screen()
	_test_saves()
	Simulation.auto_advance = true
	app.queue_free()
	await t.frames(2)
	GameSession.end_session()


func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)


func _moor_at(port_id: StringName) -> void:
	var state := GameSession.get_state_snapshot()
	state.location_id = port_id
	state.vessel_status = SessionState.STATUS_MOORED
	state.vessel_position = catalog.get_port(port_id).get_geo_position()
	state.voyage = null
	state.planned_route = null
	state.anchor = AnchorState.new()
	GameSession.replace_state(state)


func _show(area: StringName) -> BoatArea:
	app.modals.clear()
	GameSession.enter_boat_area(area, &"start")
	app._show_current_boat_area()
	await _settle()
	return app.router.current_screen as BoatArea


## Before a screenshot: no old notices, and the screen's fade-in done.
func _quiet() -> void:
	for toast in app.toasts.get_children():
		toast.queue_free()
	await t.get_tree().create_timer(0.5).timeout
	await t.frames(2)


func _plan(from: StringName, to: StringName) -> PlannedRoute:
	var r := router.plan_route(from, catalog.get_port(from).get_geo_position(), [] as Array[Vector2], to)
	return r.route


func _uses(route: PlannedRoute, canal_id: StringName) -> bool:
	for p in route.path:
		var canal := router.canal_at(p)
		if not canal.is_empty() and canal.id == canal_id:
			return true
	return false


# --- Canals ---------------------------------------------------------------------------------

func _test_canal_routes() -> void:
	var ids := router.canals.map(func(c: Dictionary) -> StringName: return c.id)
	t.check(&"kiel" in ids and &"suez" in ids and &"bab_el_mandeb" in ids, "[canals] Kiel, Suez and Bab-el-Mandeb links load (%s)" % [ids])
	var kiel := _plan(&"kiel", &"cuxhaven")
	t.check(kiel != null and _uses(kiel, &"kiel") and kiel.get_distance_nm() < 120.0 and router.validate_route(kiel) == "",
		"[kiel] Kiel -> Cuxhaven through the Kiel Canal: %d nm, valid (was 495 nm round Skagen)" % (roundi(kiel.get_distance_nm()) if kiel else -1))
	var back := _plan(&"bremerhaven", &"kiel")
	t.check(back != null and _uses(back, &"kiel") and back.get_distance_nm() < 140.0, "[kiel] and back from Bremerhaven: %d nm" % (roundi(back.get_distance_nm()) if back else -1))
	var suez := _plan(&"limassol", &"noumea")
	t.check(suez != null and _uses(suez, &"suez") and _uses(suez, &"bab_el_mandeb") and suez.get_distance_nm() < 10000.0
		and router.validate_route(suez) == "", "[suez] Limassol -> Noumea through Suez and the Red Sea: %d nm, valid (was 13,344 nm)" % (
			roundi(suez.get_distance_nm()) if suez else -1))
	var panama := _plan(&"castries", &"panama_city")
	var colon := _plan(&"colon", &"panama_city")
	t.check(panama != null and colon != null and colon.get_distance_nm() < 60.0 and router.validate_route(panama) == "",
		"[panama] the Panama passage still works (Colón -> Panama City %d nm)" % (roundi(colon.get_distance_nm()) if colon else -1))
	var baltic := []
	for pair in [[&"nynashamn", &"sundsvall"], [&"nynashamn", &"mariehamn"], [&"visby", &"lulea"], [&"nynashamn", &"helsinki"]]:
		var route := _plan(pair[0], pair[1])
		baltic.append(route != null and router.validate_route(route) == "")
	t.check(baltic.all(func(ok: bool) -> bool: return ok),
		"[stockholm] the Baltic around Stockholm: Nynäshamn to Sundsvall, Mariehamn and Helsinki, Visby to Luleå (no project-defined Stockholm passage exists)")
	# No shortcut elsewhere: a canal reach is only accepted along its canal.
	t.check(not router.is_canal_segment(Vector2(9.5, 54.0), Vector2(10.5, 55.0)) and not router.is_canal_segment(Vector2(32.3, 31.2), Vector2(34.5, 29.5)),
		"[canals] a straight line across the land near a canal is not a canal reach")


func _test_canal_voyage() -> void:
	_moor_at(&"kiel")
	var error := GameSession.plan_route_to(&"cuxhaven")
	t.check(error == "" and GameSession.get_planned_route() != null, "[kiel] planned from Kiel to Cuxhaven (%s)" % error)
	var route := GameSession.get_planned_route()
	GameSession.depart()
	var in_canal := false
	var afloat := true
	var saved_ok := false
	var aground := []
	for i in 400:
		Simulation.advance(300.0)
		if not GameSession.is_underway():
			break
		var at := GameSession.get_vessel_position()
		# Afloat, or on a berth link from a port's own coordinate (validate_route allows it).
		var on_berth_link := GeoMath.distance_to_segment_nm(at, route.path[0], route.path[1]) < 0.2 \
			or GeoMath.distance_to_segment_nm(at, route.path[-1], route.path[-2]) < 0.2
		if not router.is_afloat(at) and not on_berth_link:
			afloat = false
			aground.append(at)
		if not router.canal_at(at).is_empty() and not saved_ok and not in_canal:
			in_canal = true
			# Saved and loaded in the canal: the boat stays where it is.
			var errors: Array[String] = []
			var copy := SessionState.from_dict(GameSession.get_state_snapshot().to_dict(), errors)
			GameSession.replace_state(copy)
			saved_ok = errors.is_empty() and GameSession.get_vessel_position().distance_to(at) < 1e-4 and GameSession.is_underway()
	t.check(in_canal and afloat, "[kiel] the boat sails through the canal itself, afloat all the way (berth links aside) (%s)" % [aground.slice(0, 4)])
	t.check(saved_ok, "[kiel] saved and loaded in the canal: the same place, the same voyage")
	t.check(GameSession.get_location_id() == &"cuxhaven" and not GameSession.is_underway(), "[kiel] and arrives at Cuxhaven")


# --- Chart --------------------------------------------------------------------------------------

func _test_chart_zoom() -> void:
	app.open_chart()
	await _settle()
	var map := app.router.current_screen as WorldMap
	if not t.check(map != null, "(setup) the chart is open"):
		return
	var view := map.get_map_view()
	for i in 40:
		view.zoom_by(1.0 / MapView.ZOOM_STEP)
	await t.frames(2)
	var smallest := view.get_zoom()
	var rect := view.get_visible_geo_rect()
	t.check(smallest >= view.get_min_zoom() - 1e-6 and rect.position.y >= -72.5 and rect.end.y <= 80.5,
		"[zoom] zoomed right out the view stays on the chart's data (%.1f° S to %.1f° N)" % [-rect.position.y, rect.end.y])
	view.center_on_geo(Vector2(10.0, 85.0))
	await t.frames(1)
	var north := view.get_visible_geo_rect()
	view.center_on_geo(Vector2(10.0, -80.0))
	await t.frames(1)
	var south := view.get_visible_geo_rect()
	t.check(north.end.y <= 80.5 and south.position.y >= -72.5, "[zoom] panned to the poles at the smallest zoom: still no empty sea beyond the data")
	view.center_on_geo(Vector2(10.15, 54.33), 60.0)
	await t.frames(1)
	t.check(view.get_zoom() > smallest * 4.0, "[zoom] and back in close to a coast (Kiel)")
	app.close_chart()
	await _settle()


## Screenshots of the canal courses on the chart (evidence; no checks).
func _test_canal_charts() -> void:
	for pair in [[&"kiel", &"cuxhaven", "cozy_chart_kiel_canal"], [&"limassol", &"noumea", "cozy_chart_suez"]]:
		_moor_at(pair[0])
		app.open_chart()
		await _settle()
		var map := app.router.current_screen as WorldMap
		map.plot_course_to(pair[1])
		await t.frames(2)
		var view := map.get_map_view()
		var region := Rect2(8.6, 53.6, 2.0, 1.2) if pair[0] == &"kiel" else Rect2(28.0, 10.0, 18.0, 23.0)
		var shown := PackedVector2Array()
		for p in map.get_draft_route().path:
			if region.has_point(p):
				shown.append(p)
		view.frame_geo_points(shown)
		await _quiet()
		await t.screenshot(pair[2])
		map.discard_changes()
		app.close_chart()
		await _settle()


func _test_route_replanning() -> void:
	_moor_at(&"palermo")
	app.open_chart()
	await _settle()
	var map := app.router.current_screen as WorldMap
	map.plot_course_to(&"limassol")
	map.apply_course()
	await t.frames(2)
	var view := map.get_map_view()
	view.frame_geo_points(GameSession.get_planned_route().path)
	await t.frames(3)
	# A plain click on the course line (the accident): no waypoint.
	var mid := GameSession.get_planned_route().path[GameSession.get_planned_route().path.size() / 2]
	var screen := view.geo_to_screen(mid)
	await t.click_at(screen)
	await t.frames(2)
	t.check(map.get_draft_waypoints().is_empty() and not map.has_unapplied_changes(),
		"[replan] a click on the course line adds no waypoint and changes nothing")
	# A waypoint let go on land (Sicily's interior) moves to open water or goes.
	var index := map.insert_waypoint(0, Vector2(14.3, 37.6))
	map.place_waypoint(index, Vector2(14.3, 37.6))
	await t.frames(2)
	var legs := map.get_draft_legs()
	var blocked := legs.filter(func(l: Dictionary) -> bool: return not l.ok)
	t.check(blocked.is_empty() and (map.get_draft_waypoints().is_empty() or router.is_point_reachable(map.get_draft_waypoints()[0])),
		"[replan] a waypoint let go on land: moved to water or taken away, no blocked line left (%s)" % map.get_course_status_text().replace("\n", " / "))
	# Replanning the same course twice leaves one clean course.
	map.plot_course_to(&"limassol")
	map.plot_course_to(&"limassol")
	await t.frames(2)
	legs = map.get_draft_legs()
	t.check(legs.size() == 1 and legs[0].ok and map.get_draft_waypoints().is_empty(), "[replan] plotting again: one course, nothing stale")
	view.frame_geo_points(GameSession.get_planned_route().path)
	await t.frames(3)
	await _quiet()
	await t.screenshot("cozy_palermo_limassol")
	map.discard_changes()
	app.close_chart()
	await _settle()


# --- Floating things ---------------------------------------------------------------------------

func _water_life(area: BoatArea) -> WaterLife:
	var found := area.find_children("*", "WaterLife", true, false)
	return found[0] if not found.is_empty() else null


func _test_debris() -> void:
	SettingsManager.set_art_style(SettingsManager.ART_ILLUSTRATED)
	var directions := []
	var course_view := SettingsManager.get_course_view()
	for destination in [&"helgoland", &"kiel"]:
		# The second heading in the course-facing view (the camera turns with the course).
		SettingsManager.set_course_view(destination == &"kiel")
		_moor_at(&"cuxhaven")
		if catalog.get_port(destination) == null:
			destination = &"bremerhaven"
		GameSession.plan_route_to(destination)
		GameSession.depart()
		Simulation.advance(900.0)
		var deck := await _show(SessionState.AREA_EXTERIOR)
		var life := _water_life(deck)
		if not t.check(life != null, "(setup) the water life is on deck"):
			return
		life.refresh()
		await t.get_tree().create_timer(0.6).timeout
		var count := life.get_sea_drifter_count()
		var before := []
		for d in life.get_sea_drifters():
			before.append(life.to_global(d.p))
		await t.get_tree().create_timer(1.0).timeout
		var forward := life.get_global_transform().x.normalized()
		var aft := 0
		var moved := 0
		var drifters := life.get_sea_drifters()
		for i in drifters.size():
			var step: Vector2 = life.to_global(drifters[i].p) - before[i]
			if step.length() > 0.5 and step.length() < 400.0:
				moved += 1
				aft += 1 if step.dot(forward) < 0.0 else 0
		directions.append([count, aft, moved, GameSession.get_vessel_speed_kn(), roundi(rad_to_deg(life.get_global_transform_with_canvas().x.angle())),
			roundi(deck.get_view_heading()), deck.is_course_view()])
		if destination == &"kiel":
			await _quiet()
			await t.screenshot("cozy_debris_course_view")
	SettingsManager.set_course_view(course_view)
	var ok := directions.all(func(d: Array) -> bool: return d[0] >= 8 and d[2] > 0 and d[1] >= d[2] * 0.8)
	t.check(ok, "[debris] at sea, %s floating things in view pass astern at two headings (count, astern, moved, kn, bow° on screen, heading°, course view: %s)" % [
		"8+", directions])
	await _quiet()
	await t.screenshot("cozy_debris_underway")
	# Speeds: becalmed, slow and fast, no wind - they pass at the boat's own speed.
	var life := _water_life(app.router.current_screen as BoatArea)
	var speeds := []
	for kn in [0.0, 2.0, 7.0]:
		life._boat_kn = kn
		life._wind_kn = 0.0
		var from := []
		for d in life.get_sea_drifters():
			from.append(d.p)
		life._move_waves(0.5)
		var total := 0.0
		var n := 0
		for i in from.size():
			var dx: float = life.get_sea_drifters()[i].p.x - from[i].x
			if absf(dx) < 100.0:
				total += dx
				n += 1
		speeds.append(snappedf(total / maxi(n, 1), 0.1))
	t.check(is_zero_approx(speeds[0]) and speeds[1] < 0.0 and is_equal_approx(speeds[2] / speeds[1], 3.5),
		"[debris] becalmed they lie still, slow and fast they pass in proportion (px per half second at 0, 2, 7 kn: %s)" % [speeds])
	# Never placed on the boat: new ones always come up clear of the hull's beam.
	var clear := true
	for i in 300:
		var d: Dictionary = life.get_sea_drifters()[i % life.get_sea_drifters().size()]
		life._respawn_sea_drifter(d, i % 2 == 0)
		clear = clear and (d.p.y < life._beam.x or d.p.y > life._beam.y)
	t.check(clear, "[debris] 300 new floating things: none placed over the hull (beam %s)" % life._beam)
	# By day, for the eye: twelve hours on, still on the way to Kiel.
	for i in 48:
		Simulation.advance(900.0)
	await _show(SessionState.AREA_EXTERIOR)
	await _quiet()
	await t.screenshot("cozy_debris_day")
	_moor_at(&"copenhagen")
	life = _water_life(await _show(SessionState.AREA_EXTERIOR))
	life.refresh()
	t.check(life.get_sea_drifter_count() == 0 and life.get_drifter_count() > 0, "[debris] moored: the harbour's own drifting things instead")


# --- Q menu -----------------------------------------------------------------------------------

func _wheel_labels() -> Dictionary:
	var labels := {}
	for item in app.get_wheel_actions():
		labels[item.id] = item.label
	return labels


func _test_wheel() -> void:
	var labels := _wheel_labels()
	t.check(labels.get(&"chart") == "Charts" and labels.get(&"log") == "log", "[wheel] moored on deck: \"Charts\" and \"log\" (%s)" % [labels.values()])
	var all_text := " ".join(labels.values())
	t.check(not "Open the chart" in all_text and not "Trim the sails" in all_text, "[wheel] no old labels left")
	GameSession.plan_route_to(&"kiel")
	GameSession.depart()
	Simulation.advance(600.0)
	await _show(SessionState.AREA_EXTERIOR)
	labels = _wheel_labels()
	# I026: the plotter and the instruments are devices at the helm: their
	# items open the focused views; the radar keeps its on/off check mark.
	t.check(labels.get(&"sail_trim") == "Trim sails" and labels.get(&"chartplotter") == "Chart plotter" and labels.get(&"instruments") == "Instruments",
		"[wheel] at the helm: \"Trim sails\", \"Chart plotter\", \"Instruments\"")
	RadarPanel.shown = false
	var wheel: ActionWheel = app.open_action_wheel()
	await t.frames(3)
	var radar := wheel.find_child("Action_radar", true, false) as Button
	var plotter := wheel.find_child("Action_chartplotter", true, false) as Button
	t.check(radar.get_meta(&"checked") == false and radar.icon != null and not plotter.has_meta(&"checked"),
		"[wheel] check marks show the real state: the radar off; the plotter opens a view (no check mark)")
	await _quiet()
	await t.screenshot("cozy_wheel_checks")
	wheel.choose(wheel.items.map(func(i: Dictionary) -> StringName: return i.id).find(&"radar"))
	await t.frames(3)
	t.check(RadarPanel.shown, "[wheel] choosing it switches the radar on")
	# Changed elsewhere: the wheel shows it.
	RadarPanel.shown = false
	wheel = app.open_action_wheel()
	await t.frames(3)
	t.check((wheel.find_child("Action_radar", true, false) as Button).get_meta(&"checked") == false, "[wheel] changed elsewhere, shown at once")
	wheel.choose(wheel.items.map(func(i: Dictionary) -> StringName: return i.id).find(&"chartplotter"))
	await t.frames(4)
	t.check(app.modals.get_top() is PlotterView, "[wheel] choosing the chart plotter opens the helm's plotter, close up")
	app.modals.clear()


# --- Coffee and the hat ----------------------------------------------------------------------

func _test_coffee_all_boats() -> void:
	var results := {}
	for id in VesselCatalog.get_default().get_ids():
		_moor_at(&"copenhagen")
		GameSession.switch_vessel(id)
		var deck := await _show(SessionState.AREA_EXTERIOR)
		var holder := deck.get_node_or_null(^"CupHolder") as CoffeeMug
		var stations := deck.get_node(^"Layout/Stations")
		var station := stations.get_node_or_null(^"CupHolder") as Node2D
		var helm := stations.get_node_or_null(^"Helm") as Node2D
		var hull: PackedVector2Array = deck._lifeline_polygon()
		var placed := holder != null and station != null and helm != null and Geometry2D.is_point_in_polygon(station.position, hull) \
			and station.position.distance_to(helm.position) >= BoatArea.CUP_HELM_CLEARANCE - 0.5
		# Hands: coffee in one, the hat in the other, then nothing needing a hand.
		GameSession.make_coffee()
		var carrying := GameSession.is_carrying_coffee() and GameSession.free_hands() == 1
		if GameSession.get_hat_status() == HatState.STORED:
			GameSession.use_hat_hook()
		GameSession.toggle_hat()
		var full := GameSession.free_hands() == 0 and GameSession.get_hat_status() == HatState.CARRIED
		var refused: bool = app.open_fishing() == null and app.open_cooking() == null and GameSession.hands_refusal() != ""
		refused = refused and Array(app.toasts.get_messages()).count(GameSession.hands_refusal()) == 1
		if id == &"starling_33":
			await t.frames(3)
			await t.screenshot("cozy_hands_full")
		app.modals.clear()
		GameSession.toggle_hat()  # back on: a hand free again
		var freed := GameSession.free_hands() == 1
		# Into the holder by the helm, and back.
		var down := GameSession.put_coffee_down()
		var in_holder := GameSession.get_coffee() == GameSession.COFFEE_HOLDER and holder != null and holder.has_mug()
		var up := GameSession.pick_up_coffee()
		var back := GameSession.is_carrying_coffee()
		# Below with the mug: onto the table, and its station appears.
		var cabin := await _show(SessionState.AREA_INTERIOR)
		GameSession.put_coffee_down()
		var table_station := cabin.get_node_or_null(^"Layout/Stations/TableMug") as Interactable
		var on_table := GameSession.get_coffee() == GameSession.COFFEE_TABLE and table_station != null and table_station.enabled
		GameSession.pick_up_coffee()
		var finished := GameSession.finish_coffee() != "" and GameSession.get_coffee() == GameSession.COFFEE_NONE and not table_station.enabled
		results[id] = [placed, carrying, full, refused, freed, in_holder, back, on_table, finished]
		if id == &"starling_33":
			GameSession.make_coffee()
			await _show(SessionState.AREA_EXTERIOR)
			await _quiet()
			await t.screenshot("cozy_coffee_in_hand")
			GameSession.put_coffee_down()
			await t.frames(2)
			await _quiet()
			await t.screenshot("cozy_cup_holder")
			GameSession.pick_up_coffee()
			GameSession.finish_coffee()
	for id: StringName in results:
		t.check((results[id] as Array).all(func(ok: bool) -> bool: return ok),
			"[coffee] %s: holder by the helm (clear of it), mug in hand, hat in the other, full hands refuse kindly, hat on frees one, holder and table both work (%s)" % [id, results[id]])
	GameSession.switch_vessel(VesselCatalog.STARTER_ID)


# --- Sleep, pins, panels, loading ---------------------------------------------------------------

func _test_sleep_memory() -> void:
	await _show(SessionState.AREA_INTERIOR)
	SettingsManager.set_sleep_hours(SettingsManager.DEFAULT_SLEEP_HOURS)
	app.open_sleep_menu()
	await t.frames(3)
	var menu := app.modals.get_top() as SleepMenu
	t.check(menu != null and menu.hours == SettingsManager.DEFAULT_SLEEP_HOURS, "[sleep] first use: the usual %d hours" % SettingsManager.DEFAULT_SLEEP_HOURS)
	menu.change_hours(3)
	app.modals.clear()
	app.open_sleep_menu()
	await t.frames(3)
	menu = app.modals.get_top() as SleepMenu
	t.check(menu.hours == SettingsManager.DEFAULT_SLEEP_HOURS + 3, "[sleep] opened again: the duration chosen last (%d h)" % menu.hours)
	await _quiet()
	await t.screenshot("cozy_sleep_compact")
	var panel := menu.find_child("Panel", true, false) as Control
	t.check(panel.size.x <= 460.0, "[compact] the sleep window is smaller (%d px wide, was 520+)" % roundi(panel.size.x))
	app.modals.clear()
	SettingsManager.set_sleep_hours(9)
	SettingsManager.load_settings()
	t.check_eq(SettingsManager.get_sleep_hours(), 9, "[sleep] kept in the settings file across a restart")
	var config := ConfigFile.new()
	config.load(SettingsManager.settings_path)
	config.set_value("gameplay", "sleep_hours", 99)
	config.save(SettingsManager.settings_path)
	SettingsManager.load_settings()
	t.check_eq(SettingsManager.get_sleep_hours(), SettingsManager.SLEEP_HOURS_MAX, "[sleep] an impossible stored value is kept within the choices")
	SettingsManager.set_sleep_hours(SettingsManager.DEFAULT_SLEEP_HOURS)


func _test_pins() -> void:
	_moor_at(&"copenhagen")
	var state := GameSession.get_state_snapshot()
	state.captains_log.visited["kiel"] = {"first": state.game_time, "arrivals": 2}
	state.captains_log.visited["visby"] = {"first": state.game_time, "arrivals": 1}
	GameSession.replace_state(state)
	await _show(SessionState.AREA_INTERIOR)
	app.open_dream_map()
	await _settle()
	await t.frames(3)
	var dream := app.router.current_screen as WorldMap
	var view := dream.get_map_view()
	var visited := GameSession.get_captains_log().get_visited_ids()
	t.check(view.visited_pins.size() == visited.size() and &"kiel" in view.visited_pins and not &"auckland" in view.visited_pins,
		"[pins] a red pin for each harbour visited, once each, and none for the others (%s)" % [view.visited_pins])
	view.reset_view()
	await t.frames(2)
	var broad := view.get_pin_groups()
	t.check(broad.size() < visited.size(), "[pins] at world zoom the Danish and German pins merge into one (%d groups for %d pins)" % [broad.size(), visited.size()])
	await _quiet()
	await t.screenshot("cozy_pins_world")
	view.center_on_geo(Vector2(11.5, 55.5), 40.0 / view.units_per_degree)
	await t.frames(3)
	var close := view.get_pin_groups()
	t.check(close.size() >= 2, "[pins] closer in they separate (%d)" % close.size())
	await _quiet()
	await t.screenshot("cozy_pins_close")
	app.close_chart()
	await _settle()
	app.open_chart()
	await _settle()
	t.check((app.router.current_screen as WorldMap).get_map_view().visited_pins.is_empty(), "[pins] not on the navigation chart")
	app.close_chart()
	await _settle()


func _test_compact_ui() -> void:
	var hud: Hud = app.hud
	await _show(SessionState.AREA_INTERIOR)
	await t.frames(3)
	var area := hud.get_node("AreaPanel") as Control
	var clock := hud.get_node("ClockPanel") as Control
	t.check(area.size.y < 101.0 and area.size.x < 533.0 and clock.size.x < 520.0,
		"[compact] location panel %dx%d, clock bar %d wide (were 533x101 and 520, UI units)" % [
		roundi(area.size.x), roundi(area.size.y), roundi(clock.size.x)])
	await _quiet()
	await t.screenshot("cozy_cabin_compact")


func _test_loading_screen() -> void:
	t.check(not LoadingScreen.wanted() or DisplayServer.get_name() != "headless", "[loading] not shown without a display (tests, servers)")
	var screen := LoadingScreen.new()
	var done := [false]
	screen.finished.connect(func() -> void: done[0] = true)
	t.add_child(screen)
	var status := (screen.find_child("Status", true, false) as Label).text
	await t.wait_until(func() -> bool: return done[0], 20.0)
	t.check(done[0] and status.contains("of 3"), "[loading] real loading steps named one by one (%s), then it fades away" % status)


func _test_saves() -> void:
	GameSession.make_coffee()
	GameSession.put_coffee_down()
	var place := GameSession.get_coffee()
	var data := GameSession.get_state_snapshot().to_dict()
	var errors: Array[String] = []
	var loaded := SessionState.from_dict(data, errors)
	t.check(errors.is_empty() and loaded.galley.coffee == place and data.galley.has("coffee"), "[save] the mug's place is saved and loaded (%s)" % place)
	data.galley.erase("coffee")
	loaded = SessionState.from_dict(data, errors)
	t.check(errors.is_empty() and loaded != null and loaded.galley.coffee == &"", "[save] a save from before has no mug and loads as it was")
	t.check_eq(SaveManager.SAVE_VERSION, 12, "[save] the save format stays 12")
