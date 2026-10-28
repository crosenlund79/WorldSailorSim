extends RefCounted
## Iteration 14: the detailed Danish waters as a player sees them. Chart views
## at several scales (regional, the islands, the Belts, the Copenhagen
## approach, close to the coast, zoomed out), a course round the land,
## sailing and anchoring in Danish waters and a Danish harbour's shore. The
## checks are light (what is shown, which layer); the pictures are the point
## in a rendered run (--screenshots=DIR).
##
## View centres are harbour positions from the catalogue and GeoNames town
## positions (cities.json, CC BY 4.0), never coordinates from memory.

const APP_SCENE := preload("res://src/app/app.tscn")
const RINGSTED := Vector2(11.79011, 55.4426)
const ODENSE := Vector2(10.38831, 55.39594)
## [screenshot, centre (port id or position), pixels per degree, detail layer expected]
const VIEWS := [
	["14_01_denmark_regional", Vector2(11.2, 55.9), 150.0, true],
	["14_02_zealand", RINGSTED, 420.0, true],
	["14_03_funen", ODENSE, 420.0, true],
	["14_04_jutland_waters", &"juelsminde", 330.0, true],
	["14_05_langeland_lohals", &"lohals", 900.0, true],
	["14_06_island_passages", &"marstal", 650.0, true],
	["14_07_copenhagen_approach", &"copenhagen", 1600.0, true],
	["14_09_close_coastal_view", &"svendborg", 3200.0, true],
]

var t: Node
var app: Node


func run(runner: Node) -> void:
	t = runner
	Simulation.auto_advance = false
	t.use_calm_wind()
	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	app.start_new_game()
	await _settle()
	await _test_chart_views()
	await _test_sailing()
	await _test_harbour_shore()
	Simulation.auto_advance = true
	app.queue_free()
	await t.frames(2)
	GameSession.end_session()
	t.use_calm_wind()


func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)


func _geo(centre: Variant) -> Vector2:
	return PortCatalog.get_default().get_port(centre).get_geo_position() if centre is StringName else centre


func _open_chart() -> WorldMap:
	app.modals.clear()
	app.open_chart()
	await _settle()
	return app.router.current_screen as WorldMap


func _test_chart_views() -> void:
	var world := await _open_chart()
	if not t.check(world != null, "[views] the chart opens"):
		return
	var map := world.get_map_view()
	for view: Array in VIEWS:
		map.center_on_geo(_geo(view[1]), float(view[2]) / map.units_per_degree)
		await t.frames(3)
		t.check(map.is_region_detail_shown("denmark") == view[3], "[views] %s: the %s layer is drawn" % [view[0], "detailed" if view[3] else "overview"])
		await t.screenshot(view[0])
	map.reset_view()
	await t.frames(3)
	t.check(not map.is_region_detail_shown("denmark"), "[views] zoomed out: the overview outline, light and consistent")
	await t.screenshot("14_10_zoomed_out")
	# A course round the land: Copenhagen to Svendborg.
	map.center_on_geo(_geo(&"copenhagen"), 300.0 / map.units_per_degree)
	await t.frames(2)
	map.center_on_geo(_geo(&"svendborg"), 300.0 / map.units_per_degree)
	await t.frames(2)
	await t.click_at(map.get_port_screen_position(&"svendborg"))
	await t.click(world.find_child("PlotButton", true, false))
	await t.frames(3)
	var draft := world.get_draft_route()
	if t.check(draft != null and SeaRouter.get_default().validate_route(draft).is_empty(), "[views] a course Copenhagen → Svendborg round Zealand"):
		map.frame_geo_points(draft.path)
		await t.frames(3)
		await t.screenshot("14_08_route_around_land")
		await t.click(world.find_child("ApplyButton", true, false))
		await t.frames(2)
	app.close_chart()
	await _settle()


func _test_sailing() -> void:
	t.set_wind(250.0, 12.0)
	if not t.check(GameSession.get_planned_route() != null and GameSession.depart() == "", "[views] (setup) under way to Svendborg"):
		return
	Simulation.advance(2.0 * 3600.0)
	GameSession.enter_boat_area(SessionState.AREA_EXTERIOR, &"start")
	app._show_current_boat_area()
	await _settle()
	await t.frames(10)
	t.check(GameSession.is_underway() and app.router.current_screen is BoatArea, "[views] sailing in Danish waters, on deck")
	app.toasts.clear()
	await t.screenshot("14_17_sailing_danish_waters")
	var chart := await _open_chart()
	if chart:
		chart.get_map_view().center_on_geo(GameSession.get_vessel_position(), 700.0 / chart.get_map_view().units_per_degree)
		await t.frames(3)
		await t.screenshot("14_17b_chart_underway_danish_waters")
		app.close_chart()
		await _settle()
	# On along the course until the coast is near enough to anchor.
	var near := false
	for i in 120:
		Simulation.advance(600.0)
		if not GameSession.is_underway():
			break
		var site := GameSession.evaluate_anchorage()
		if site.ok and String(site.class) != String(AnchorSite.CLASS_POOR) and _harbour_nm(GameSession.get_vessel_position()) > 3.0:
			near = true
			break
	if t.check(near and GameSession.drop_anchor(5, 0.8).error == "", "[views] at anchor near the Danish coast"):
		var world := await _open_chart()
		if world:
			world.get_map_view().center_on_geo(GameSession.get_vessel_position(), 2400.0 / world.get_map_view().units_per_degree)
			await t.frames(3)
			app.toasts.clear()
			await t.screenshot("14_18_anchorage_near_coast")
			app.close_chart()
			await _settle()
		GameSession.enter_boat_area(SessionState.AREA_EXTERIOR, &"start")
		app._show_current_boat_area()
		await _settle()
		await t.screenshot("14_18b_anchorage_on_deck")
		GameSession.raise_anchor()


## Distance (nm) to the nearest harbour.
func _harbour_nm(geo: Vector2) -> float:
	var best := INF
	for port in PortCatalog.get_default().ports:
		best = minf(best, GeoMath.distance_nm(geo, port.get_geo_position()))
	return best


func _test_harbour_shore() -> void:
	var state := GameSession.get_state_snapshot()
	state.voyage = null
	state.location_id = &"svendborg"
	state.vessel_status = SessionState.STATUS_MOORED
	state.vessel_position = PortCatalog.get_default().get_port(&"svendborg").get_geo_position()
	state.planned_route = null
	GameSession.replace_state(state)
	GameSession.enter_boat_area(SessionState.AREA_EXTERIOR, &"from_boatyard")
	app.modals.clear()
	app._show_current_boat_area()
	await _settle()
	var deck := app.router.current_screen as BoatArea
	var front := await TestQuay.go_up(t, app)
	var yard := front.get_station(QuayLayout.BOATYARD) if front else null
	if t.check(yard != null, "[views] Svendborg, a major service harbour, has its boatyard on the quay"):
		front.player.position = yard.position + Vector2(0, 6)
		await t.physics_frames(4)
		t.check(front.player.get_focused_interactable() == yard and yard.highlight_outline.size() >= 3,
			"[views] the boatyard's storefront lights up, no circle")
		await t.screenshot("14_19_fleet_in_harbour")
		app.open_boatyard()
		await t.frames(4)
		t.check(app.modals.get_top() is BoatyardMenu, "[views] the boatyard shows the fleet")
		await t.screenshot("14_19b_boatyard_fleet")
		app.modals.clear()
		await t.frames(2)
