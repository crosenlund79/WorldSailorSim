extends RefCounted
## Iteration 004: three vessels, the boatyard and the sprite-ready vessel
## architecture. Checks the data and scenes of every vessel, that every
## station and spawn point can be walked to, the boatyard (in harbour only),
## life aboard each vessel (chart, sleep, companion, sails and engine),
## persistence and migration, and sprite replacement with fallback.

const APP_SCENE := preload("res://src/app/app.tscn")
const DEMO_PROFILE := preload("res://data/vessels/starling_33_visuals_demo.tres")
const DECK_STATIONS: Array[StringName] = [&"companionway", &"helm", &"boatyard"]
const CABIN_STATIONS: Array[StringName] = [&"companionway", &"nav_table", &"bed"]
const DECK_SPAWNS: Array[StringName] = [&"start", &"from_cabin", &"from_boatyard"]
const CABIN_SPAWNS: Array[StringName] = [&"start", &"from_deck", &"v_berth"]
const SAIL_MARKERS: Array[String] = ["Mast", "Tack", "BoomEnd", "Traveller", "JibSheetLead", "SpinnakerSheetLead"]
const PLAYER_RADIUS := 20.0
## A station is usable when the player's centre gets this close to its shape
## (the player's reach circle has a radius of 46).
const USE_DISTANCE := 40.0
const GRID := 10.0

var t: Node
var app: Node


func run(runner: Node) -> void:
	t = runner
	_test_catalog_and_definitions()
	_test_scenes_instantiate()
	_test_performance_profiles()
	_test_sprite_fallback_order()

	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	Simulation.auto_advance = false
	app.start_new_game()
	await _settle()

	await _test_reachability_all()
	await _test_boatyard_menu()
	await _test_boatyard_refused_underway()
	for id in VesselCatalog.get_default().get_ids():
		await _test_life_aboard(id)
	await _test_sprite_swap_on_monohull()
	await _test_time_controls_on_other_vessel()
	await _test_persistence()

	Simulation.auto_advance = true
	app.queue_free()
	await t.frames(2)
	GameSession.end_session()
	t.use_calm_wind()


# --- Data and scenes ---------------------------------------------------------------

func _test_catalog_and_definitions() -> void:
	var catalog := VesselCatalog.get_default()
	t.check_eq(catalog.get_ids(), [&"arctic_wanderer_26", &"starling_33", &"halcyon_40", &"petrel_36"] as Array[StringName], "[vessels] four vessels, starter first")
	t.check_eq(catalog.get_starter().id, &"arctic_wanderer_26", "[vessels] the Arctic Wanderer 26 is the starter boat (0.100b)")
	t.check_eq(SessionState.create_new(&"copenhagen", SessionState.AREA_EXTERIOR, &"start").vessel_id, &"arctic_wanderer_26",
		"[vessels] a new game starts aboard the Arctic Wanderer 26")
	# Official names (0.100b); the internal ids, and so every save, stay the same.
	var names := {}
	for vessel in catalog.vessels:
		names[vessel.id] = vessel.display_name
	t.check_eq(names, {&"arctic_wanderer_26": "Arctic Wanderer 26", &"starling_33": "Wing 33", &"halcyon_40": "Clam 40", &"petrel_36": "Frogleap 36"},
		"[vessels] official names: Arctic Wanderer 26, Wing 33, Clam 40, Frogleap 36")
	var small := catalog.get_starter().performance
	var wing := catalog.get_vessel(&"starling_33").performance
	t.check(small.length_ft < wing.length_ft and small.max_sail_speed_kn < wing.max_sail_speed_kn and is_equal_approx(small.engine_speed_kn, 5.0),
		"[vessels] the 26 is smaller and slower under sail than the Wing 33, with the usual 5 kn engine")
	var hulls := {}
	for vessel in catalog.vessels:
		t.check(vessel.validate().is_empty(), "[vessels] %s is complete (%s)" % [vessel.id, ", ".join(vessel.validate())])
		t.check(not vessel.display_name.is_empty() and not vessel.description.is_empty() and vessel.specs.size() >= 3,
			"[vessels] %s has a name, description and specs" % vessel.id)
		t.check(vessel.deck_visual_scene != null and vessel.visual_profile != null, "[vessels] %s has a visual scene and profile" % vessel.id)
		t.check(vessel.visual_profile.art_folder == "res://assets/vessels/%s" % vessel.id, "[vessels] %s art folder follows the convention" % vessel.id)
		hulls[vessel.hull_type] = true
	t.check_eq(hulls.keys().size(), 3, "[vessels] monohull, catamaran and trimaran")
	t.check(catalog.get_vessel(&"no_such_boat") == null and not catalog.has_vessel(&""), "[vessels] unknown ids are not found")


func _check_layout(scene: Node, area: String, label: String) -> void:
	var visual := scene.get_node_or_null("Visual") as VesselVisual
	t.check(visual != null, "[scenes] %s %s has a Visual" % [label, area])
	var slots: Array[StringName] = VesselVisualProfile.DECK_SLOTS if area == "deck" else VesselVisualProfile.CABIN_SLOTS
	var missing := []
	for slot in slots:
		if slot in [&"BoomVisual", &"MainSailVisual", &"HeadSailVisual", &"SpinnakerVisual"]:
			continue  # drawn by the SailRig
		if visual == null or visual.get_slot(slot) == null:
			missing.append(slot)
	t.check(missing.is_empty(), "[scenes] %s %s has every visual slot %s" % [label, area, missing if missing else ""])
	var physics_in_visual := visual.find_children("*", "CollisionObject2D", true, false) if visual else []
	t.check(physics_in_visual.is_empty(), "[scenes] %s %s Visual holds no collision or interaction" % [label, area])
	var stations := {}
	for node in scene.get_node("Layout/Stations").get_children():
		stations[(node as Interactable).interaction_id] = true
	for id in (DECK_STATIONS if area == "deck" else CABIN_STATIONS):
		t.check(stations.has(id), "[scenes] %s %s station '%s'" % [label, area, id])
	for spawn in (DECK_SPAWNS if area == "deck" else CABIN_SPAWNS):
		t.check(scene.get_node_or_null("Layout/SpawnPoints/%s" % spawn) is Marker2D, "[scenes] %s %s spawn '%s'" % [label, area, spawn])
	if area == "deck":
		for marker in SAIL_MARKERS:
			t.check(scene.get_node_or_null("Layout/SailMarkers/%s" % marker) is Marker2D, "[scenes] %s sail marker %s" % [label, marker])
		t.check(scene.get_node_or_null("SailRig") is SailRig and scene.get_node_or_null("Surroundings/Mooring") != null,
			"[scenes] %s deck has a SailRig and a mooring" % label)
	else:
		for spot in CompanionState.ALL_SPOT_IDS:
			t.check(scene.get_node_or_null("Layout/CompanionSpots/%s" % spot) is Marker2D, "[scenes] %s companion spot '%s'" % [label, spot])
		t.check(scene.get_node_or_null("Companion") is ShipCompanion, "[scenes] %s cabin has its companion" % label)
	t.check(scene.get_node_or_null("Player") is Player and scene.get_node_or_null("Camera2D") is Camera2D, "[scenes] %s %s has player and camera" % [label, area])


func _test_scenes_instantiate() -> void:
	for vessel in VesselCatalog.get_default().vessels:
		for area in ["deck", "cabin"]:
			var packed := vessel.deck_scene if area == "deck" else vessel.cabin_scene
			var scene := packed.instantiate() if packed else null
			if not t.check(scene is BoatArea, "[scenes] %s %s instantiates" % [vessel.id, area]):
				continue
			t.check_eq((scene as BoatArea).area_id, SessionState.AREA_EXTERIOR if area == "deck" else SessionState.AREA_INTERIOR,
				"[scenes] %s %s area id" % [vessel.id, area])
			_check_layout(scene, area, vessel.id)
			scene.free()
		var visual := vessel.deck_visual_scene.instantiate() as VesselVisual
		t.check(visual != null and visual.canvas.has_area(), "[scenes] %s deck visual works alone (preview)" % vessel.id)
		if visual:
			visual.free()


func _test_performance_profiles() -> void:
	var catalog := VesselCatalog.get_default()
	var mono := catalog.get_vessel(&"starling_33").performance
	var cat := catalog.get_vessel(&"halcyon_40").performance
	var tri := catalog.get_vessel(&"petrel_36").performance
	t.check(mono != cat and cat != tri and mono != tri, "[performance] each vessel has its own profile")
	t.check(tri.max_sail_speed_kn > cat.max_sail_speed_kn and cat.max_sail_speed_kn > mono.max_sail_speed_kn,
		"[performance] top speed: trimaran > catamaran > monohull")
	t.check(cat.sail_speed_kn(12.0, 90.0) > mono.sail_speed_kn(12.0, 90.0) and tri.sail_speed_kn(12.0, 90.0) > cat.sail_speed_kn(12.0, 90.0),
		"[performance] on a beam reach in 12 kn the multihulls are faster")
	t.check(mono.angle_efficiency(42.0) > cat.angle_efficiency(42.0), "[performance] the monohull points higher than the catamaran")
	t.check(cat.engine_speed_kn > mono.engine_speed_kn and cat.engine_speed_kn > tri.engine_speed_kn, "[performance] the catamaran's twin engines are the strongest")
	var rows := BoatyardMenu.compare_rows(catalog.get_vessel(&"petrel_36"))
	# I027 Tier 3: five sailing rows, then guests, private cabins and passages (Accommodation).
	t.check(rows.size() == 8 and rows[0][1] == "%.1f kn" % tri.max_sail_speed_kn and rows[5][1] == "%d / %d" % [
		Accommodation.safe_guest_count(&"petrel_36"), Accommodation.overnight_guest_count(&"petrel_36")],
		"[performance] the boatyard comparison is computed from the profile and the accommodation data")


func _test_sprite_fallback_order() -> void:
	var image := Image.create(224, 80, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 0, 0, 0.5))
	var texture := ImageTexture.create_from_image(image)
	var profile := VesselVisualProfile.new()
	profile.art_folder = "res://assets/vessels/does_not_exist"
	t.check(profile.get_texture(&"HullBase") == null and profile.get_source(&"HullBase") == "procedural",
		"[sprites] a missing file falls back to procedural art")
	profile.hull_base = texture
	t.check(profile.get_texture(&"HullBase") == texture and profile.get_source(&"HullBase") == "profile", "[sprites] an assigned texture is used first")
	profile.procedural_only = true
	t.check(profile.get_texture(&"HullBase") == null, "[sprites] procedural_only shows the placeholder art")
	t.check(DEMO_PROFILE.get_source(&"Coachroof") == "file" and DEMO_PROFILE.get_source(&"HullBase") == "procedural",
		"[sprites] the demo coachroof PNG is picked up by its conventional name; other slots stay procedural")
	t.check_eq(DEMO_PROFILE.conventional_path(&"Coachroof"), "res://assets/vessels/starling_33/demo/deck/coachroof.png", "[sprites] conventional path")
	t.check_eq(DEMO_PROFILE.conventional_path(&"FurnitureVisual"), "res://assets/vessels/starling_33/demo/cabin/furniture.png", "[sprites] cabin slots live in cabin/")

	# Applying sprites to a visual-only scene, and an unexpected aspect ratio.
	var visual := (VesselCatalog.get_default().get_starter().deck_visual_scene.instantiate()) as VesselVisual
	t.add_child(visual)
	var odd := VesselVisualProfile.new()
	odd.deck_base = ImageTexture.create_from_image(Image.create(300, 300, false, Image.FORMAT_RGBA8))
	visual.apply(odd)
	var slot := visual.get_slot(&"DeckBase")
	t.check(slot.is_sprite() and is_equal_approx(slot.get_sprite().scale.x * 300.0, visual.canvas.size.x), "[sprites] a sprite is scaled to the canvas width")
	var hidden := true
	for child in slot.get_children():
		if child != slot.get_sprite():
			hidden = hidden and not (child as CanvasItem).visible
	t.check(hidden, "[sprites] the slot's procedural art is hidden under the sprite")
	visual.apply(null)
	t.check(not slot.is_sprite() and slot.get_child(0).visible, "[sprites] back to procedural art")
	visual.free()


# --- Walking: every station and spawn point can be reached ---------------------------

## Reachable player positions (grid) from `from`, using the real collision.
func _walkable_cells(area: BoatArea, from: Vector2) -> Array[Vector2]:
	var space := area.get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = PLAYER_RADIUS
	query.shape = circle
	query.collision_mask = area.player.collision_mask
	query.exclude = [area.player.get_rid()]
	var free := func(p: Vector2) -> bool:
		query.transform = Transform2D(0.0, area.to_global(p))
		return space.intersect_shape(query, 1).is_empty()
	var cells: Array[Vector2] = []
	if not free.call(from):
		return cells
	var seen := {from: true}
	var queue: Array[Vector2] = [from]
	var bounds := area.walkable_bounds.grow(60.0)
	while not queue.is_empty():
		var p: Vector2 = queue.pop_back()
		cells.append(p)
		for step in [Vector2(GRID, 0), Vector2(-GRID, 0), Vector2(0, GRID), Vector2(0, -GRID)]:
			var q: Vector2 = p + step
			if seen.has(q) or not bounds.has_point(q):
				continue
			seen[q] = true
			if free.call(q):
				queue.append(q)
	return cells


static func _distance_to_station(station: Interactable, p: Vector2) -> float:
	var shape := (station.get_node("CollisionShape2D") as CollisionShape2D).shape
	var local := p - station.position
	if shape is CircleShape2D:
		return maxf(local.length() - (shape as CircleShape2D).radius, 0.0)
	var half := (shape as RectangleShape2D).size / 2.0
	var d := (local.abs() - half).max(Vector2.ZERO)
	return d.length()


## Places from which the station is in reach, nearest first.
static func _use_points(station: Interactable, cells: Array[Vector2]) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for c in cells:
		if _distance_to_station(station, c) <= USE_DISTANCE:
			points.append(c)
	points.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_to(station.position) < b.distance_to(station.position))
	return points


func _test_reachability_all() -> void:
	for id in VesselCatalog.get_default().get_ids():
		_force_vessel(id)
		for area_id in [SessionState.AREA_EXTERIOR, SessionState.AREA_INTERIOR]:
			await _show(area_id, &"start")
			var area := app.router.current_screen as BoatArea
			var start := area.get_spawn_position(&"start")
			var cells := _walkable_cells(area, start)
			var label := "%s %s" % [id, "deck" if area_id == SessionState.AREA_EXTERIOR else "cabin"]
			t.check(cells.size() > 200, "[walk] %s: the player can move around (%d places)" % [label, cells.size()])
			var cell_set := {}
			for c in cells:
				cell_set[c] = true
			for spawn in (DECK_SPAWNS if area_id == SessionState.AREA_EXTERIOR else CABIN_SPAWNS):
				var at := area.get_spawn_position(spawn)
				var near := false
				for c in cells:
					if c.distance_to(at) <= GRID:
						near = true
						break
				t.check(near, "[walk] %s: spawn '%s' is free and connected" % [label, spawn])
			var fine: Array[Vector2] = []
			for station: Interactable in area.get_node("Layout/Stations").get_children():
				if not station.enabled:
					continue
				var reachable := not _use_points(station, cells).is_empty()
				if not reachable:
					# Narrow side decks (the Wing 33's) need a finer grid to find
					# the way the player fits through (Iteration 13: the windlass).
					if fine.is_empty():
						fine = TestWalkability.walkable_cells(area, start, 5.0)
					reachable = not _use_points(station, fine).is_empty()
				t.check(reachable, "[walk] %s: '%s' can be walked to" % [label, station.interaction_id])
			var bounds_ok := true
			for c in cells:
				bounds_ok = bounds_ok and area.walkable_bounds.grow(PLAYER_RADIUS).has_point(c)
			t.check(bounds_ok, "[walk] %s: the walkable area stays inside the boat (walkable_bounds)" % label)
	_force_vessel(&"starling_33")
	await _show(SessionState.AREA_EXTERIOR, &"start")


# --- Boatyard -------------------------------------------------------------------------

func _test_boatyard_menu() -> void:
	await _show(SessionState.AREA_EXTERIOR, &"start")
	var deck := app.router.current_screen as BoatArea
	# I026: the boatyard has its own building on the quay, up the pontoon's
	# walkway (the pontoon's old station is gone).
	var walkway := deck.get_walkway()
	t.check(GameSession.can_change_vessel() and walkway != null and walkway.enabled and walkway.visible,
		"[boatyard] in harbour the walkway leads up to the quay, where the boatyard is")
	# Walk there and use it like a player.
	var used := await _use_station(deck, BoatArea.WALKWAY_ID)
	await _settle()
	used = used and await TestQuay.use_door(t, app, QuayLayout.BOATYARD)
	var menu := app.modals.get_top() as BoatyardMenu
	t.check(used and menu != null, "[boatyard] its door on the quay opens the boatyard")
	if menu == null:
		return
	await t.frames(3)
	t.check_eq(menu.selected.id, &"starling_33", "[boatyard] it shows the current boat first")
	t.check(menu.find_child("ChooseButton", true, false).disabled, "[boatyard] the current boat cannot be chosen again")
	var list := menu.find_child("VesselList", true, false)
	t.check_eq(list.get_child_count(), 4, "[boatyard] four boats to browse")
	var before_time := GameSession.get_game_time()
	var before_location := GameSession.get_location_id()
	var before_companion := GameSession.get_companion().to_dict()
	for id in VesselCatalog.get_default().get_ids():
		menu.select(id)
		await t.frames(2)
		var preview := menu.get_preview_root()
		var vessel := VesselCatalog.get_default().get_vessel(id)
		t.check(preview != null and preview.get_child(0) is VesselVisual and preview.find_children("*", "CollisionObject2D", true, false).is_empty(),
			"[boatyard] %s preview shows the art only" % id)
		t.check((menu.find_child("NameLabel", true, false) as Label).text == vessel.display_name
			and (menu.find_child("HullLabel", true, false) as Label).text == vessel.get_hull_type_name()
			and (menu.find_child("Description", true, false) as Label).text == vessel.description,
			"[boatyard] %s name, hull type and description" % id)
		await t.screenshot("40_boatyard_%s" % id)
	menu.select(&"starling_33")
	await t.press_action(&"ui_down")
	t.check_eq(menu.selected.id, &"halcyon_40", "[boatyard] arrow keys browse")
	t.check(GameSession.get_vessel_id() == &"starling_33" and is_equal_approx(GameSession.get_game_time(), before_time),
		"[boatyard] browsing changes nothing")
	await t.click(menu.find_child("ChooseButton", true, false) as Button)
	await _settle()
	var area := app.router.current_screen as BoatArea
	t.check_eq(GameSession.get_vessel_id(), &"halcyon_40", "[boatyard] moved aboard the catamaran")
	t.check(app.modals.is_empty() and area != null and area.area_id == SessionState.AREA_EXTERIOR
		and area.scene_file_path.contains("halcyon_40"), "[boatyard] standing on the catamaran's deck")
	t.check(area.player.position.distance_to(area.get_spawn_position(&"from_boatyard")) < 1.0, "[boatyard] at the boatyard spawn point")
	t.check(is_equal_approx(GameSession.get_game_time(), before_time) and GameSession.get_location_id() == before_location
		and GameSession.get_companion().to_dict() == before_companion, "[boatyard] time, harbour and companion are kept")
	t.check(not GameSession.get_propulsion().initialised, "[boatyard] stale propulsion data is reset")
	t.check(_toast_contains("Welcome aboard the Clam 40"), "[boatyard] the player is told")
	t.check_eq(app.get_node("Screen").get_child_count(), 1, "[boatyard] exactly one boat area (no duplicate scenes)")
	t.check_eq(_count(BoatArea), 1, "[boatyard] no stale boat area left behind")
	t.check_eq(GameSession.switch_vessel(&"atlantis_99"), "Unknown boat 'atlantis_99'.", "[boatyard] an unknown boat is refused")
	await t.screenshot("41_catamaran_deck_after_switch")
	# And back again, through App.
	app.switch_vessel(&"starling_33")
	await _settle()
	t.check(GameSession.get_vessel_id() == &"starling_33" and (app.router.current_screen as BoatArea).scene_file_path.contains("starling_33"),
		"[boatyard] switching back to the monohull")


func _test_boatyard_refused_underway() -> void:
	t.set_wind(270.0, 14.0)
	GameSession.plan_route_to(&"kiel")
	t.check_eq(GameSession.depart(), "", "(setup) underway to Kiel")
	await _show(SessionState.AREA_EXTERIOR, &"start")
	var deck := app.router.current_screen as BoatArea
	var yard := deck.get_node("Layout/Stations/Boatyard") as Interactable
	t.check(not GameSession.can_change_vessel() and not yard.enabled and not yard.visible, "[boatyard] underway the boatyard station is gone")
	app.open_boatyard()
	await t.frames(2)
	t.check(app.modals.is_empty() and _toast_contains("only open while you are moored"), "[boatyard] opening it underway is refused")
	t.check(GameSession.switch_vessel(&"petrel_36") != "" and GameSession.get_vessel_id() == &"starling_33", "[boatyard] switching underway is refused")
	_restart_in_port()
	await _show(SessionState.AREA_EXTERIOR, &"start")


# --- Life aboard each vessel ----------------------------------------------------------

func _test_life_aboard(id: StringName) -> void:
	_restart_in_port()
	t.check_eq(GameSession.switch_vessel(id), "", "(setup) aboard %s" % id)
	var vessel := GameSession.get_vessel_definition()
	await _show(SessionState.AREA_EXTERIOR, &"from_boatyard")

	# Deck -> cabin through the companionway.
	var deck := app.router.current_screen as BoatArea
	t.check(await _use_station(deck, &"companionway"), "[%s] the companionway leads below" % id)
	await _settle()
	var cabin := app.router.current_screen as BoatArea
	t.check(cabin != null and cabin.area_id == SessionState.AREA_INTERIOR and cabin.scene_file_path == vessel.cabin_scene.resource_path,
		"[%s] in its own cabin" % id)
	if cabin == null:
		return

	# The companion: exactly one, on this cabin's marker, and it can be petted.
	var companion := cabin.find_child("Companion", true, false) as ShipCompanion
	var spot := GameSession.get_companion().spot
	var marker := cabin.get_node("Layout/CompanionSpots/%s" % spot) as Marker2D
	t.check(_count(ShipCompanion) == 1 and companion.visible and companion.position == marker.position,
		"[%s] the companion rests on the cabin's '%s' marker" % [id, spot])
	companion.pet()
	t.check(companion.is_reacting(), "[%s] the companion can be petted" % id)
	for other in CompanionState.get_spot_ids(GameSession.get_companion().kind):
		_set_spot(other)
		await t.frames(1)
		t.check(companion.position == cabin.get_node("Layout/CompanionSpots/%s" % other).position, "[%s] companion moves to '%s'" % [id, other])
	await t.screenshot("42_cabin_%s" % id)

	# The chart from the nav station, and back.
	t.check(await _use_station(cabin, &"nav_table"), "[%s] the nav station opens the chart" % id)
	await _settle()
	t.check(app.router.current_screen is WorldMap, "[%s] the chart is open" % id)
	app.close_chart()
	await _settle()
	cabin = app.router.current_screen as BoatArea
	t.check(cabin != null and cabin.scene_file_path == vessel.cabin_scene.resource_path, "[%s] back in its cabin after the chart" % id)

	# Sleep at the berth: wake beside it.
	t.check(await _use_station(cabin, &"bed"), "[%s] the berth offers sleep" % id)
	t.check(app.modals.get_top() is SleepMenu, "[%s] the sleep dialog opens" % id)
	var before := GameSession.get_game_time()
	app.sleep_for(2.0)
	await _settle()
	cabin = app.router.current_screen as BoatArea
	var wake := cabin.get_spawn_position(&"v_berth")
	t.check(is_equal_approx(GameSession.get_game_time() - before, 2.0 * 3600.0) and cabin.player.position.distance_to(wake) < 1.0,
		"[%s] two hours later the player wakes beside the berth" % id)

	# Underway: navigation, speed from this vessel's profile, sails and engine.
	t.set_wind(270.0, 14.0)
	t.check_eq(GameSession.plan_route_to(&"kiel"), "", "[%s] a course to Kiel" % id)
	t.check_eq(GameSession.depart(), "", "[%s] departs" % id)
	Simulation.advance(1800.0)
	var state := GameSession.get_propulsion()
	var profile := vessel.performance
	t.check(GameSession.get_vessel_profile() == profile, "[%s] the simulation sails with this vessel's profile" % id)
	var expected := profile.engine_speed_kn if state.is_motoring() else profile.sail_speed_kn(state.wind_speed_kn, state.true_wind_angle)
	t.check(state.initialised and absf(state.speed_kn - expected) < 0.05,
		"[%s] speed %.2f kn matches its profile (%.2f kn, %s)" % [id, state.speed_kn, expected, state.mode])
	await _show(SessionState.AREA_EXTERIOR, &"start")
	deck = app.router.current_screen as BoatArea
	var rig := deck.get_node("SailRig") as SailRig
	var markers := deck.get_node("Layout/SailMarkers")
	t.check(rig.mast == (markers.get_node("Mast") as Marker2D).position and rig.tack == (markers.get_node("Tack") as Marker2D).position,
		"[%s] the sails are rigged on this deck's markers" % id)
	var sailing := GameSession.get_propulsion()
	sailing.mode = PropulsionState.MODE_SAIL
	sailing.true_wind_angle = 95.0
	sailing.spinnaker = false
	GameSession.set_propulsion(sailing)
	await t.wait_until(func() -> bool: return absf(rig.set_amount - 1.0) < 0.01 and rig.spinnaker_amount < 0.01, 5.0)
	var shape: Dictionary = rig.get_shape()
	t.check(not rig.is_furled() and not rig.is_spinnaker_visible() and (shape.main.clew as Vector2).y < 0.0,
		"[%s] main and jib set to leeward on a beam reach, no spinnaker" % id)
	await t.screenshot("43_deck_sailing_%s" % id)
	# The same sails with sprites stretched over them (panels as stripes).
	var procedural_shape: Dictionary = rig.get_shape(2.0)
	rig.apply_profile(_striped_sail_profile())
	t.check(rig.main_texture != null and rig.jib_texture != null and rig.get_shape(2.0) == procedural_shape,
		"[%s] sail sprites follow the same sail shape" % id)
	await t.frames(3)
	await t.screenshot("43b_deck_sail_sprites_%s" % id)
	rig.apply_profile(vessel.visual_profile)
	sailing.true_wind_angle = 150.0
	sailing.spinnaker = true
	GameSession.set_propulsion(sailing)
	await t.wait_until(func() -> bool: return absf(rig.spinnaker_amount - 1.0) < 0.01, 6.0)
	await t.frames(30)
	var kite: Dictionary = rig.get_shape().spinnaker
	t.check(rig.is_spinnaker_visible() and absf((kite.tack as Vector2).distance_to(rig.mast) - rig.spinnaker_pole) < 0.5
		and kite.front[kite.front.size() / 2].x > rig.tack.x, "[%s] the spinnaker flies ahead of the bow on its pole (tack %s, front %s, pole %.0f)" % [
			id, kite.tack, kite.front[kite.front.size() / 2], rig.spinnaker_pole])
	await t.screenshot("44_deck_spinnaker_%s" % id)
	var motoring := GameSession.get_propulsion()
	motoring.mode = PropulsionState.MODE_ENGINE
	motoring.spinnaker = false
	GameSession.set_propulsion(motoring)
	await t.wait_until(func() -> bool: return rig.is_furled() and not rig.is_spinnaker_visible(), 6.0)
	t.check(rig.is_furled() and AudioManager.is_loop_playing(app.ENGINE_LOOP), "[%s] motoring: sails furled, engine running" % id)
	_restart_in_port()


# --- Sprites in the game ------------------------------------------------------------

func _layout_snapshot(area: BoatArea) -> Dictionary:
	var snapshot := {}
	for node in area.get_node("Layout").find_children("*", "Node2D", true, false):
		snapshot[str(area.get_node("Layout").get_path_to(node))] = (node as Node2D).global_position
	return snapshot


func _test_sprite_swap_on_monohull() -> void:
	_restart_in_port()
	await _show(SessionState.AREA_EXTERIOR, &"start")
	var deck := app.router.current_screen as BoatArea
	# Since Visual Identity V01 the Starling shows its illustrated prototype by
	# default; this check starts from its classic (procedural) profile.
	deck.apply_visual_profile(GameSession.get_vessel_definition().visual_profile)
	var visual := deck.get_node("Visual") as VesselVisual
	var procedural := _layout_snapshot(deck)
	var coachroof := visual.get_slot(&"Coachroof")
	t.check(not coachroof.is_sprite(), "[sprites] the monohull starts with procedural art")
	await t.screenshot("45_monohull_procedural")
	deck.apply_visual_profile(DEMO_PROFILE)
	await t.physics_frames(2)
	t.check(coachroof.is_sprite() and coachroof.get_sprite().texture.resource_path.ends_with("demo/deck/coachroof.png"),
		"[sprites] the demo coachroof sprite replaces the procedural coachroof")
	t.check(not visual.get_slot(&"HullBase").is_sprite(), "[sprites] slots without a sprite keep their procedural art")
	var sprite := coachroof.get_sprite()
	t.check(sprite.global_position.is_equal_approx(deck.to_global(visual.canvas.position))
		and is_equal_approx(sprite.texture.get_width() * sprite.scale.x, visual.canvas.size.x), "[sprites] the sprite covers exactly the canvas")
	t.check_eq(_layout_snapshot(deck), procedural, "[sprites] collision, stations, spawns and markers are unchanged by the art")
	# Collision still comes from the layout: the coachroof still blocks the player.
	var roof := deck.get_node("Layout/Collision/Coachroof") as Node2D
	t.check(deck.player.test_move(Transform2D(0.0, deck.to_global(Vector2(-330, 0))), Vector2(500, 0)), "[sprites] the coachroof still blocks the player")
	t.check(roof is BoatFixture, "[sprites] collision is the BoatFixture, not the sprite")
	# The cabin after the swap, then back on deck with the sprite (screenshot).
	await _show(SessionState.AREA_EXTERIOR, &"start")
	deck = app.router.current_screen as BoatArea
	deck.apply_visual_profile(DEMO_PROFILE)
	t.check(await _use_station(deck, &"helm"), "[sprites] the helm still works with the sprite")
	await t.frames(2)
	await t.screenshot("46_monohull_demo_coachroof_sprite")
	# Sail sprites: stretched over the live sail shape.
	var sails := VesselVisualProfile.new()
	var cloth := Image.create(256, 128, false, Image.FORMAT_RGBA8)
	cloth.fill(Color("#E8DCC0"))
	sails.main_sail = ImageTexture.create_from_image(cloth)
	var rig := deck.get_node("SailRig") as SailRig
	var shape_before: Dictionary = rig.get_shape(1.0)
	rig.apply_profile(sails)
	t.check(rig.main_texture == sails.main_sail and rig.get_shape(1.0) == shape_before, "[sprites] a sail sprite does not change the sail's shape")
	deck.apply_visual_profile(GameSession.get_vessel_definition().visual_profile)


func _test_time_controls_on_other_vessel() -> void:
	_restart_in_port()
	GameSession.switch_vessel(&"petrel_36")
	await _show(SessionState.AREA_EXTERIOR, &"from_boatyard")
	GameSession.set_time_scale(20)
	var before := GameSession.get_game_time()
	Simulation.tick(1.0)
	t.check(GameSession.get_game_time() - before > 19.0, "[time] 20x runs aboard the trimaran")
	GameSession.set_paused(true)
	before = GameSession.get_game_time()
	Simulation.tick(1.0)
	t.check_eq(GameSession.get_game_time(), before, "[time] pause holds aboard the trimaran")
	app.open_chart()
	await _settle()
	t.check(app.router.current_screen is WorldMap and app.hud.visible, "[time] the chart opens with the clock bar")
	app.close_chart()
	await _settle()
	t.check((app.router.current_screen as BoatArea).scene_file_path.contains("petrel_36"), "[time] closing the chart returns to the trimaran")
	GameSession.set_time_scale(1)


# --- Persistence -------------------------------------------------------------------

func _save_load(slot: int, label: String) -> Dictionary:
	var before := {"vessel": GameSession.get_vessel_id(), "area": GameSession.get_boat_area(),
		"position": GameSession.get_player_position(), "underway": GameSession.is_underway(), "time": GameSession.get_game_time()}
	t.check_eq(SaveManager.save_to_slot(slot, GameSession.get_state_snapshot()), OK, "[persistence] saved %s" % label)
	app.show_main_menu()
	await _settle()
	app.load_slot(slot)
	await _settle()
	var area := app.router.current_screen as BoatArea
	t.check(GameSession.get_vessel_id() == before.vessel and area != null
		and area.scene_file_path == GameSession.get_vessel_definition().get_area_scene(before.area).resource_path,
		"[persistence] %s: back aboard %s in the same area" % [label, before.vessel])
	t.check(area != null and area.player.position.distance_to(before.position) < 1.0 and GameSession.is_underway() == before.underway
		and is_equal_approx(GameSession.get_game_time(), before.time), "[persistence] %s: position, voyage and time restored" % label)
	SaveManager.delete_slot(slot)
	return before


func _test_persistence() -> void:
	_restart_in_port()
	t.check_eq(GameSession.get_vessel_id(), &"arctic_wanderer_26", "[persistence] a new game is aboard the Arctic Wanderer 26")
	await _show(SessionState.AREA_INTERIOR, &"from_deck")
	await _save_load(2, "in the Arctic Wanderer 26's cabin")
	await _show(SessionState.AREA_EXTERIOR, &"start")
	await _save_load(2, "on the Arctic Wanderer 26's deck")
	GameSession.switch_vessel(&"halcyon_40")
	await _show(SessionState.AREA_INTERIOR, &"from_deck")
	await _save_load(2, "in the catamaran's cabin")
	await _show(SessionState.AREA_EXTERIOR, &"start")
	await _save_load(2, "on the catamaran's deck")
	_restart_in_port()
	GameSession.switch_vessel(&"petrel_36")
	t.set_wind(270.0, 14.0)
	GameSession.plan_route_to(&"kiel")
	GameSession.depart()
	Simulation.advance(3600.0)
	await _show(SessionState.AREA_EXTERIOR, &"start")
	await _save_load(2, "underway on the trimaran")
	_restart_in_port()
	GameSession.switch_vessel(&"halcyon_40")
	GameSession.switch_vessel(&"starling_33")
	await _show(SessionState.AREA_EXTERIOR, &"from_boatyard")
	await _save_load(2, "after switching back to the monohull")

	# The save file stores the id.
	SaveManager.save_to_slot(2, GameSession.get_state_snapshot())
	var text := FileAccess.get_file_as_string(SaveManager.save_dir.path_join("slot_2.json"))
	var data: Dictionary = JSON.parse_string(text)
	t.check(data.version == SaveManager.SAVE_VERSION and data.session.vessel.id == "starling_33", "[persistence] saves record the vessel id (v%d)" % SaveManager.SAVE_VERSION)

	# An Iteration 003b save (v4, no vessel) loads aboard the monohull.
	GameSession.switch_vessel(&"petrel_36")
	var session: Dictionary = GameSession.get_state_snapshot().to_dict()
	session.vessel.erase("id")
	_write_slot(3, 4, session)
	var loaded := SaveManager.load_from_slot(3)
	t.check(loaded.is_ok() and loaded.state.vessel_id == &"starling_33", "[migration] a v4 save loads aboard the Starling 33 (Wing 33), not today's starter")

	# An unknown id: the starter boat, and the player is told.
	session = GameSession.get_state_snapshot().to_dict()
	session.vessel.id = "galleon_99"
	_write_slot(3, SaveManager.SAVE_VERSION, session)
	app.show_main_menu()
	await _settle()
	app.load_slot(3)
	await _settle()
	await t.frames(2)
	var area := app.router.current_screen as BoatArea
	t.check(GameSession.get_vessel_id() == &"arctic_wanderer_26" and area != null and area.scene_file_path.contains("arctic_wanderer_26"),
		"[migration] an unknown vessel id falls back to the starter boat")
	t.check(_toast_contains("galleon_99"), "[migration] and the player is told")
	t.check(GameSession.get_companion() != null, "[migration] the rest of the save is kept")
	SaveManager.delete_slot(2)
	SaveManager.delete_slot(3)


func _write_slot(slot: int, version: int, session: Dictionary) -> void:
	var wrapper := {"format": "next_harbor_save", "version": version, "game_version": "0.4.0",
		"saved_at_unix": 1790000000.0, "saved_at_utc": "2026-09-21T12:53:20Z", "session": session}
	var file := FileAccess.open(SaveManager.save_dir.path_join("slot_%d.json" % slot), FileAccess.WRITE)
	file.store_string(JSON.stringify(wrapper, "", true, true))
	file.close()


# --- Helpers ------------------------------------------------------------------------

## Test sail art: cream cloth with darker panel seams, and a darker boom.
func _striped_sail_profile() -> VesselVisualProfile:
	var cloth := Image.create(512, 256, false, Image.FORMAT_RGBA8)
	cloth.fill(Color("#EDE3CA"))
	for x in range(0, 512, 64):
		cloth.fill_rect(Rect2i(x, 0, 4, 256), Color("#9C8E6C"))
	var kite := cloth.duplicate() as Image
	kite.fill_rect(Rect2i(0, 96, 512, 64), Color("#C79F6D"))
	var boom := Image.create(256, 16, false, Image.FORMAT_RGBA8)
	boom.fill(Color("#4A555A"))
	var profile := VesselVisualProfile.new()
	profile.main_sail = ImageTexture.create_from_image(cloth)
	profile.head_sail = profile.main_sail
	profile.spinnaker = ImageTexture.create_from_image(kite)
	profile.boom = ImageTexture.create_from_image(boom)
	return profile


## Walks the player into reach of the station with this interaction id and
## presses E. Returns true when that station was the one used.
func _use_station(area: BoatArea, interaction_id: StringName) -> bool:
	var station: Interactable = null
	for node: Interactable in area.get_node("Layout/Stations").get_children():
		if node.interaction_id == interaction_id:
			station = node
	if station == null:
		return false
	var cells := _walkable_cells(area, area.player.position)
	if cells.is_empty():
		cells = _walkable_cells(area, area.get_spawn_position(&"start"))
	var tries := 0
	for p in _use_points(station, cells):
		area.player.position = p
		await t.physics_frames(3)
		var focused := area.player.get_focused_interactable()
		if focused == station:
			await t.press_action(&"interact")
			await t.frames(2)
			return true
		tries += 1
		if tries > 12:
			break
	return false


func _force_vessel(id: StringName) -> void:
	var state := GameSession.get_state_snapshot()
	state.vessel_id = id
	GameSession.replace_state(state)


func _set_spot(spot: StringName) -> void:
	var state := GameSession.get_state_snapshot()
	state.companion.spot = spot
	GameSession.replace_state(state)


## A fresh game moored in Copenhagen (keeps the app running).
func _restart_in_port() -> void:
	app.modals.clear()
	GameSession.start_new_session()
	t.use_calm_wind()


func _show(area: StringName, spawn: StringName) -> void:
	app.modals.clear()
	GameSession.enter_boat_area(area, spawn)
	app._show_current_boat_area()
	await _settle()


func _count(type: Variant) -> int:
	var count := 0
	for node in t.get_tree().root.find_children("*", "", true, false):
		if is_instance_of(node, type) and node.is_inside_tree() and not (node is ShipCompanion and (node.preview or not node.is_visible_in_tree())):
			count += 1
	return count


func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)


func _toast_contains(text: String) -> bool:
	for message in app.toasts.get_messages():
		if text in message:
			return true
	return false
