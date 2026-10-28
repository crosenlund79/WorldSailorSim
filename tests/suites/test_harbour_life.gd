extends RefCounted
## Iteration 12, "A Little Harbour Life": walking ashore over a gangplank on
## every boat, harbour facilities from data (Copenhagen with a boatyard,
## Lohals without), object highlights instead of activation circles, Go
## Ashore events, and the course-facing deck view. Focused checks: what a
## player would notice going wrong.

const APP_SCENE := preload("res://src/app/app.tscn")
const W := preload("res://tests/helpers/walkability.gd")
const DECK := SessionState.AREA_EXTERIOR
const CABIN := SessionState.AREA_INTERIOR

var t: Node
var app: Node


func run(runner: Node) -> void:
	t = runner
	Simulation.auto_advance = false
	t.use_calm_wind()
	_test_facility_data()
	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	app.start_new_game()
	await _settle()
	await _test_shore_on_every_boat()
	await _test_highlights()
	await _test_lohals()
	await _test_go_ashore()
	await _test_departure_closes_the_shore()
	await _test_save_load_ashore()
	await _test_course_view()
	Simulation.auto_advance = true
	app.queue_free()
	await t.frames(2)
	GameSession.end_session()
	t.use_calm_wind()


func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)


func _show(area: StringName, spawn: StringName) -> BoatArea:
	app.modals.clear()
	GameSession.enter_boat_area(area, spawn)
	app._show_current_boat_area()
	await _settle()
	return app.router.current_screen as BoatArea


## Puts the game in `port_id`, moored (a harbour change without sailing).
func _moor_in(port_id: StringName) -> void:
	var state := GameSession.get_state_snapshot()
	state.location_id = port_id
	state.vessel_status = SessionState.STATUS_MOORED
	state.vessel_position = PortCatalog.get_default().get_port(port_id).get_geo_position()
	GameSession.replace_state(state)


# --- Facilities -------------------------------------------------------------------

func _test_facility_data() -> void:
	var copenhagen := HarbourFacilities.for_port(&"copenhagen")
	t.check(copenhagen.grocery and copenhagen.boatyard and copenhagen.go_ashore, "[facilities] Copenhagen: groceries, boatyard and Go Ashore")
	var lohals := HarbourFacilities.for_port(&"lohals")
	t.check(PortCatalog.get_default().get_port(&"lohals") != null, "[facilities] Lohals is a harbour in the catalogue")
	t.check(not lohals.boatyard and lohals.go_ashore and lohals.grocery, "[facilities] Lohals: no boatyard; Go Ashore and groceries")
	var kiel := HarbourFacilities.for_port(&"kiel")
	t.check(kiel.get_ids() == HarbourFacilities.ALL, "[facilities] a harbour without its own entry keeps every service (Kiel)")
	# Iteration 14: the small Danish harbours have no boatyard either; every
	# other harbour keeps one, and only some can haul out.
	var without: Array[StringName] = []
	var haul_outs := 0
	for port in PortCatalog.get_default().ports:
		var facilities := HarbourFacilities.for_port(port.id)
		if not facilities.boatyard:
			without.append(port.id)
		haul_outs += 1 if facilities.has(HarbourFacilities.HAUL_OUT) else 0
	var small: Array[StringName] = [&"lohals", &"gilleleje", &"dragor", &"rodvig", &"stege", &"nysted", &"kerteminde",
		&"aeroskobing", &"juelsminde", &"ebeltoft",
		# Iteration 16: the small island harbours abroad.
		&"arrecife", &"bequia", &"puerto_ayora", &"taiohae", &"atuona", &"fakarava", &"bora_bora", &"avarua", &"pago_pago",
		&"nukualofa", &"lautoka",
		# I021: the small harbours of the wider world.
		&"dingle", &"isafjordur", &"symi", &"essaouira", &"st_helena"]
	without.sort()
	small.sort()
	t.check(without == small, "[facilities] only Lohals and the small Danish, island and fishing harbours lack a boatyard (%s)" % [without])
	t.check(haul_outs > 0 and haul_outs < PortCatalog.get_default().ports.size() / 2,
		"[facilities] only some harbours can haul out (%d of %d)" % [haul_outs, PortCatalog.get_default().ports.size()])
	t.check(copenhagen.has(HarbourFacilities.HAUL_OUT) and copenhagen.get_tier() == HarbourFacilities.TIER_MAJOR,
		"[facilities] Copenhagen's boatyard hauls out (major service harbour)")
	t.check(lohals.get_tier() == HarbourFacilities.TIER_SMALL and not lohals.has(HarbourFacilities.HAUL_OUT),
		"[facilities] Lohals is a small harbour without a haul-out")
	var svendborg := HarbourFacilities.for_port(&"svendborg")
	var korsor := HarbourFacilities.for_port(&"korsor")
	var stege := HarbourFacilities.for_port(&"stege")
	t.check(svendborg.get_tier() == HarbourFacilities.TIER_MAJOR and korsor.get_tier() == HarbourFacilities.TIER_LARGER
		and stege.get_tier() == HarbourFacilities.TIER_SMALL, "[facilities] tiers: Svendborg major, Korsør larger, Stege small")


# --- Shore access ---------------------------------------------------------------------

func _test_shore_on_every_boat() -> void:
	for id in VesselCatalog.get_default().get_ids():
		if id != GameSession.get_vessel_id():
			GameSession.switch_vessel(id)
		var deck := await _show(DECK, &"from_boatyard")
		var shore := deck.get_shore_access()
		if not t.check(shore != null and shore.is_active(), "[shore] %s: the gangplank is out in harbour" % id):
			continue
		var start := deck.get_spawn_position(&"start")
		var cells := W.walkable_cells(deck, start)
		var landing := shore.get_landing_point()
		t.check(W.nearest(cells, landing).distance_to(landing) <= W.GRID, "[shore] %s: from the cockpit you can walk down the gangplank onto the pontoon" % id)
		var back := W.walkable_cells(deck, landing)
		var companionway := deck.get_node("Layout/Stations/Companionway") as Interactable
		t.check(not W.use_points(companionway, back).is_empty(), "[shore] %s: and from the pontoon back aboard to the companionway" % id)
		t.check(W.nearest(back, start).distance_to(start) <= W.GRID,
			"[shore] %s: boat, plank and pontoon are one area: from the pontoon the cockpit is reachable too" % id)
		for facility in HarbourFacilities.ALL:
			var station := deck.get_shore_station(facility)
			t.check(station != null and station.enabled and station.visible and station.position.y > shore.get_rail_y()
				and not W.use_points(station, cells).is_empty(), "[shore] %s: the %s stands ashore and can be walked to" % [id, facility])
		var signs := deck.get_harbour_dressing().get_sign_ids()
		t.check(signs.size() == 3, "[shore] %s: three signs on the pontoon (%s)" % [id, signs])
		# Walk it like a player: down the plank and back up.
		await t.hold_actions([&"move_down"], 1.4)
		t.check(shore.is_player_ashore() and deck.player.position.y > shore.get_pontoon_rect().position.y,
			"[shore] %s: walking down the gangplank puts the captain ashore (y %d)" % [id, roundi(deck.player.position.y)])
		await t.get_tree().create_timer(1.2).timeout
		await t.screenshot("172_gangplank_%s" % id)
		var camera := deck.get_node("Camera2D") as Camera2D
		t.check(absf(camera.offset.y - deck.get_shore_camera_target()) < 2.0 and (deck.get_shore_camera_target() > 0.0
			or deck.get_viewport_rect().size.y > 1000.0), "[shore] %s: the view follows the captain ashore (offset %d)" % [id, roundi(camera.offset.y)])
		await t.hold_actions([&"move_up"], 1.6)
		t.check(not shore.is_player_ashore() and not shore.is_off_the_boat(deck.player.position),
			"[shore] %s: and walking up the plank brings them back aboard" % id)
	GameSession.switch_vessel(VesselCatalog.STARTER_ID)


# --- Highlights -----------------------------------------------------------------------

func _test_highlights() -> void:
	t.check(not Interactable.debug_show_areas, "[highlight] interaction areas are not drawn in normal play")
	for id in VesselCatalog.get_default().get_ids():
		if id != GameSession.get_vessel_id():
			GameSession.switch_vessel(id)
		var cabin := await _show(CABIN, &"from_deck")
		await t.frames(2)
		var missing := []
		for station_id in [&"nav_table", &"bed", &"provisions", &"hat", &"companionway"]:
			var station := _station(cabin, station_id)
			# A doorway without steps (the Clam's saloon door) lights up its opening.
			var needs_object: bool = not (station_id == &"companionway" and id == &"halcyon_40")
			if station == null or (station.highlight_outline.size() < 3 if needs_object else station.get_highlight_points().size() < 3):
				missing.append(station_id)
		t.check(missing.is_empty(), "[highlight] %s cabin: the chart table, berth, galley, hat hook and steps are what lights up (%s)" % [id, missing])
	GameSession.switch_vessel(VesselCatalog.STARTER_ID)
	var deck := await _show(DECK, &"from_boatyard")
	await t.frames(2)
	for facility in [HarbourFacilities.GROCERY, HarbourFacilities.BOATYARD, HarbourFacilities.GO_ASHORE]:
		var station := deck.get_shore_station(facility)
		var outline := station.get_highlight_points()
		var center := Vector2.ZERO
		for p in outline:
			center += station.to_global(p)
		center /= maxf(outline.size(), 1)
		t.check(station.highlight_outline.size() >= 3 and center.y > station.global_position.y,
			"[highlight] the %s station highlights its sign board" % facility)
	# Walk up to the grocery sign: it lights up, with its prompt.
	var grocery := deck.get_shore_station(HarbourFacilities.GROCERY)
	deck.player.position = grocery.position + Vector2(0, -26)
	await t.physics_frames(4)
	t.check(deck.player.get_focused_interactable() == grocery and app.hud.get_prompt() == "Visit the grocery store",
		"[highlight] standing at the grocery sign focuses it: '%s'" % app.hud.get_prompt())
	await t.screenshot("173_highlight_grocery")
	var yard := deck.get_shore_station(HarbourFacilities.BOATYARD)
	deck.player.position = yard.position + Vector2(0, -26)
	await t.physics_frames(4)
	t.check(deck.player.get_focused_interactable() == yard, "[highlight] and the boatyard sign likewise")
	await t.screenshot("174_highlight_boatyard")


func _station(area: BoatArea, interaction_id: StringName) -> Interactable:
	for node in area.find_children("*", "Interactable", true, false):
		if (node as Interactable).interaction_id == interaction_id:
			return node
	return null


# --- Lohals (no boatyard) -------------------------------------------------------------

func _test_lohals() -> void:
	_moor_in(&"copenhagen")
	var deck := await _show(DECK, &"from_boatyard")
	await t.screenshot("175_copenhagen_with_boatyard")
	_moor_in(&"lohals")
	deck = await _show(DECK, &"from_boatyard")
	var yard := deck.get_shore_station(HarbourFacilities.BOATYARD)
	t.check(yard != null and not yard.enabled and not yard.visible and not yard.monitorable,
		"[lohals] no boatyard station, and no invisible target left behind")
	t.check(not HarbourFacilities.BOATYARD in deck.get_harbour_dressing().get_sign_ids(), "[lohals] no boatyard sign")
	var label := deck.mooring.get_node_or_null(^"BoatyardSign") as Label
	t.check(label != null and not label.visible, "[lohals] the classic boatyard label is hidden too")
	t.check(deck.get_shore_station(HarbourFacilities.GROCERY).enabled and deck.get_shore_station(HarbourFacilities.GO_ASHORE).enabled,
		"[lohals] the grocery store and Go Ashore are there")
	var funds := GameSession.get_funds()
	t.check(GameSession.switch_vessel(&"halcyon_40").contains("no boatyard") and GameSession.get_vessel_id() == VesselCatalog.STARTER_ID,
		"[lohals] changing boats is refused: there is no boatyard")
	GameSession.set_condition_for_testing(60.0)
	t.check(GameSession.repair_vessel().contains("no boatyard") and GameSession.get_condition() < 100.0 and GameSession.get_funds() == funds,
		"[lohals] repairs are refused and nothing is charged")
	GameSession.set_condition_for_testing(100.0)
	app.open_boatyard()
	await t.frames(2)
	t.check(app.modals.is_empty() and _toast_contains("There is no boatyard in Lohals"), "[lohals] the boatyard cannot be opened; the player is told why")
	await t.screenshot("176_lohals_without_boatyard")
	_moor_in(&"copenhagen")


func _toast_contains(text: String) -> bool:
	for message in app.toasts.get_messages():
		if text in message:
			return true
	return false


# --- Go Ashore -----------------------------------------------------------------------

func _test_go_ashore() -> void:
	GameSession.end_session()
	app.start_new_game()
	await _settle()
	var deck := await _show(DECK, &"from_boatyard")
	var station := deck.get_shore_station(HarbourFacilities.GO_ASHORE)
	deck.player.position = station.position + Vector2(0, -26)
	await t.physics_frames(4)
	t.check(deck.player.get_focused_interactable() == station and app.hud.get_prompt() == "Go ashore", "[ashore] the Go Ashore sign: 'Go ashore'")
	await t.press_action(&"interact")
	await t.frames(3)
	var menu := app.modals.get_top() as GoAshoreMenu
	if not t.check(menu != null and menu.get_event_id() != "" and not menu.get_choice_buttons().is_empty(),
			"[ashore] E opens a small harbour event with its choices"):
		return
	var event_id := menu.get_event_id()
	var event := ShoreEvents.find(&"copenhagen", event_id)
	await t.screenshot("177_go_ashore_event")
	var funds := GameSession.get_funds()
	var renown := GameSession.get_lifetime_renown()
	var time := GameSession.get_game_time()
	var choice: Dictionary = event.choices[0]
	await t.click(menu.get_choice_buttons()[0])
	await t.frames(2)
	t.check(GameSession.get_funds() == funds - int(choice.cost) and GameSession.get_lifetime_renown() == renown + int(choice.renown),
		"[ashore] '%s': costs %s, pays %d renown the first time" % [choice.label, GameSession.format_money(int(choice.cost)), int(choice.renown)])
	t.check(absf(GameSession.get_game_time() - time - float(choice.minutes) * 60.0) < 1.0, "[ashore] and %d minutes pass" % int(choice.minutes))
	var moments := GameSession.get_shore_moments()
	t.check(moments.size() == 1 and String(moments[0].text).contains(event.title), "[ashore] a notable moment for the Captain's Log: '%s'" % (moments[0].text if moments else ""))
	t.check(menu.get_choice_buttons().is_empty() and menu.get_text().contains("renown"), "[ashore] the panel tells what happened; only Return remains")
	await t.screenshot("178_go_ashore_outcome")
	app.modals.clear()
	# No farming: straight back, the harbour is "resting", with nothing to gain.
	renown = GameSession.get_lifetime_renown()
	funds = GameSession.get_funds()
	app.open_go_ashore()
	await t.frames(2)
	menu = app.modals.get_top() as GoAshoreMenu
	t.check(menu != null and menu.get_choice_buttons().is_empty() and GameSession.get_shore_event().get("resting", false),
		"[ashore] going straight back: a pleasant stroll, no new event")
	t.check(GameSession.apply_shore_choice(event_id, 0).error != "" and GameSession.get_lifetime_renown() == renown and GameSession.get_funds() == funds,
		"[ashore] the same choice cannot be paid again")
	app.modals.clear()
	# Later, something new; the first event never pays twice.
	Simulation.advance((ShoreEvents.REST_HOURS + 1.0) * 3600.0)
	var next := GameSession.get_shore_event()
	t.check(next.has("event") and next.event.id != event_id, "[ashore] hours later a different event is offered (%s)" % (next.event.id if next.has("event") else "none"))
	var record := ShoreEvents.record_id(&"copenhagen", event_id)
	t.check(GameSession.get_objective_progress().completed.has(record) and int(GameSession.get_objective_progress().completed[record].count) == 1,
		"[ashore] the outing is recorded once")
	# Saved and loaded: the outings and their rewards are kept.
	t.check_eq(SaveManager.save_to_slot(3, GameSession.get_state_snapshot()), OK, "(setup) saved after an outing")
	var loaded := SaveManager.load_from_slot(3)
	t.check(loaded.is_ok() and loaded.state.progress.completed.has(record) and loaded.state.progress.lifetime_renown == GameSession.get_lifetime_renown(),
		"[ashore] a save after harbour events keeps them (no reward can be earned twice after loading)")
	SaveManager.delete_slot(3)
	t.check(ShoreEvents.for_port(&"lohals").size() == ShoreEvents.GENERIC.size() + 1 and ShoreEvents.for_port(&"kiel").size() == ShoreEvents.GENERIC.size(),
		"[ashore] %d generic events, plus a few harbour variants (Copenhagen, Lohals)" % ShoreEvents.GENERIC.size())


# --- Course view ----------------------------------------------------------------------

func _test_course_view() -> void:
	SettingsManager.set_course_view(true)
	GameSession.end_session()
	app.start_new_game()
	await _settle()
	var deck := await _show(DECK, &"start")
	var camera := deck.get_node("Camera2D") as Camera2D
	t.check(is_zero_approx(camera.rotation) and not deck.is_course_view(), "[course] moored, the boat lies bow-right as always")
	t.set_wind(270.0, 14.0)
	GameSession.plan_route_to(&"kiel")
	GameSession.depart()
	Simulation.advance(600.0)
	deck = await _show(DECK, &"start")
	camera = deck.get_node("Camera2D") as Camera2D
	var heading := Simulation.get_current_heading()
	t.check(deck.is_course_view() and absf(angle_difference(camera.rotation, deg_to_rad(90.0 - BoatArea.octant_for(heading) * 45.0))) < 0.01,
		"[course] underway the bow points along the course's octant on screen (heading %d°, north up)" % roundi(heading))
	t.check(is_zero_approx(app.hud.get_global_transform().get_rotation()), "[course] the HUD stays upright")
	var life := deck.get_water_life()
	life.refresh()
	t.check(life.get_wind_direction().dot(deck.wind_direction_on_deck()) > 0.999, "[course] the waves keep their world direction")
	var names := {0.0: "north", 90.0: "east", 180.0: "south", 270.0: "west"}
	for h: float in names:
		deck.view_heading_override = h
		deck._update_camera()
		life.refresh()
		await t.get_tree().create_timer(BoatArea.ZOOM_TRANSITION_S + 0.2).timeout
		var bow := (deck.get_viewport().get_canvas_transform() * deck.to_global(Vector2(400, 0))) \
			- (deck.get_viewport().get_canvas_transform() * deck.to_global(Vector2.ZERO))
		var expected := Vector2.from_angle(deg_to_rad(h - 90.0))
		t.check(bow.normalized().dot(expected) > 0.99 and camera.zoom.x >= BoatArea.COURSE_MIN_ZOOM - 0.001,
			"[course] heading %s: the bow points %s on screen, zoom %.2f (never below %.2f)" % [names[h], names[h], camera.zoom.x, BoatArea.COURSE_MIN_ZOOM])
		await t.screenshot("179_course_%s" % names[h])
	# Walking stays screen-relative: with the bow up, "up" walks forward.
	deck.view_heading_override = 0.0
	deck._update_camera()
	await t.get_tree().create_timer(BoatArea.ZOOM_TRANSITION_S + 0.2).timeout
	var start := deck.player.position
	await t.hold_actions([&"move_up"], 0.3)
	t.check(deck.player.position.x > start.x + 20.0 and absf(deck.player.position.y - start.y) < 10.0,
		"[course] the movement keys follow the screen: with the bow up, W walks towards the bow")
	deck.view_heading_override = NAN
	# Arriving, the boat turns back to its harbour orientation.
	t.use_calm_wind()
	Simulation.advance(60.0 * 3600.0)
	if GameSession.is_underway():
		Simulation.advance(60.0 * 3600.0)
	await t.get_tree().create_timer(BoatArea.ZOOM_TRANSITION_S + 0.3).timeout
	deck = app.router.current_screen as BoatArea
	camera = deck.get_node("Camera2D") as Camera2D
	t.check(not GameSession.is_underway() and is_zero_approx(snappedf(camera.rotation, 0.001)), "[course] in harbour the deck is upright again")
	# Switched off, the boat stays bow-right underway.
	SettingsManager.set_course_view(false)
	GameSession.plan_route_to(&"copenhagen")
	GameSession.depart()
	await t.get_tree().create_timer(BoatArea.ZOOM_TRANSITION_S + 0.3).timeout
	t.check(not deck.is_course_view() and is_zero_approx(snappedf(camera.rotation, 0.001)), "[course] with the setting off the boat keeps pointing right")
	SettingsManager.set_course_view(SettingsManager.DEFAULT_COURSE_VIEW)
	GameSession.end_session()
	app.start_new_game()
	await _settle()


# --- Departure, saving ----------------------------------------------------------------

func _test_departure_closes_the_shore() -> void:
	var deck := await _show(DECK, &"from_boatyard")
	var shore := deck.get_shore_access()
	deck.player.position = shore.get_landing_point()
	await t.physics_frames(3)
	t.check(shore.is_off_the_boat(deck.player.position), "(setup) the captain is ashore")
	t.set_wind(270.0, 14.0)
	GameSession.plan_route_to(&"kiel")
	t.check_eq(GameSession.depart(), "", "(setup) the boat departs")
	await t.physics_frames(3)
	t.check(not shore.is_active() and not shore.is_off_the_boat(deck.player.position) and deck.player.position.y < shore.get_rail_y(),
		"[shore] setting off, the gangplank comes in and the captain is aboard")
	var none_open := true
	for facility in HarbourFacilities.ALL:
		none_open = none_open and not deck.get_shore_station(facility).enabled
	t.check(none_open, "[shore] underway no shore service can be used")
	t.use_calm_wind()
	GameSession.end_session()
	app.start_new_game()
	await _settle()


func _test_save_load_ashore() -> void:
	var deck := await _show(DECK, &"from_boatyard")
	var shore := deck.get_shore_access()
	var ashore := shore.get_landing_point() + Vector2(60, 4)
	deck.player.position = ashore
	await t.physics_frames(3)
	t.check_eq(SaveManager.save_to_slot(3, GameSession.get_state_snapshot()), OK, "(setup) saved while ashore")
	app.show_main_menu()
	await _settle()
	app.load_slot(3)
	await _settle()
	deck = app.router.current_screen as BoatArea
	t.check(deck != null and deck.area_id == DECK and deck.player.position.distance_to(ashore) < 2.0 and deck.get_shore_access().is_active(),
		"[shore] a game saved ashore loads with the captain on the pontoon")
	SaveManager.delete_slot(3)
