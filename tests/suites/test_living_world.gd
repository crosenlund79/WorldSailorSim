extends RefCounted
## 0.100b "A Living Little World": the expressive sailor, the living water
## (moored and underway), the illustrated decks and cabins of all four boats
## and the wider framing underway. Presentation only, so the checks are lean:
## the art exists, follows the game and never touches it.

const APP_SCENE := preload("res://src/app/app.tscn")
const DECK := SessionState.AREA_EXTERIOR
const CABIN := SessionState.AREA_INTERIOR

var t: Node
var app: Node


func run(runner: Node) -> void:
	t = runner
	Simulation.auto_advance = false
	t.use_calm_wind()
	SettingsManager.set_art_style(SettingsManager.ART_ILLUSTRATED)
	# The 0.100b framing (bow right, 0.86x underway); the course view of
	# Iteration 12 is tested in test_harbour_life.
	SettingsManager.set_course_view(false)
	_test_atmospheres()
	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	app.start_new_game()
	await _settle()
	await _test_sailor()
	await _test_moored_water()
	await _test_all_boats()
	await _test_underway()
	SettingsManager.set_course_view(SettingsManager.DEFAULT_COURSE_VIEW)
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


# --- Water atmospheres (data) ---------------------------------------------------------

func _test_atmospheres() -> void:
	t.check_eq(WaterLife.atmosphere_for(&"copenhagen"), WaterLife.ATMOSPHERE_URBAN, "[water] Copenhagen's harbour art asks for a city harbour")
	var island := &""
	var minor := &""
	for port in PortCatalog.get_default().ports:
		if HarbourArt.for_port(port.id) != null:
			continue
		if port.island and island == &"":
			island = port.id
		elif not port.island and port.importance == 1 and minor == &"":
			minor = port.id
	t.check(island != &"" and WaterLife.atmosphere_for(island) == WaterLife.ATMOSPHERE_COASTAL,
		"[water] an island harbour gets the sheltered coastal water (%s)" % island)
	t.check(minor != &"" and WaterLife.atmosphere_for(minor) == WaterLife.ATMOSPHERE_MARINA,
		"[water] a small mainland harbour gets the open marina water (%s)" % minor)
	t.check_eq(WaterLife.atmosphere_for(&""), WaterLife.ATMOSPHERE_MARINA, "[water] no harbour: plain marina water")


# --- The sailor -----------------------------------------------------------------------

func _test_sailor() -> void:
	var deck := await _show(DECK, &"start")
	var player := deck.player
	var body := player.get_node("CollisionShape2D") as CollisionShape2D
	t.check(body != null and is_equal_approx((body.shape as CircleShape2D).radius, 20.0), "[sailor] the body collision is unchanged (radius 20)")
	t.check(is_zero_approx(player.get_swing()), "[sailor] standing still, the arms hang at rest")
	var left := SailorDrawing.hand_position(Vector2.RIGHT, 0.0, -1.0)
	var right := SailorDrawing.hand_position(Vector2.RIGHT, 0.0, 1.0)
	t.check(absf(left.y) > 12.0 and absf(left.y + right.y) < 0.01 and is_equal_approx(left.x, right.x), "[sailor] two hands, one at each shoulder")
	t.check(not SailorDrawing.hand_position(Vector2.RIGHT, 1.0, 1.0).is_equal_approx(right), "[sailor] the arms swing")
	# Walking measured by distance (up to two strides), on the foredeck
	# towards the bow. From the start spot, beside the companionway, the
	# walk met deck fittings after 31 px (down) or 52 px (forward), under one
	# stride: the swing then reached 0.60 at best, which failed now and then.
	# From here there are about 72 px before the next fitting: more than one
	# stride, which swings each arm both ways. The companion is moved aside.
	player.position = Vector2(250, 0)
	var companion := deck.get_node_or_null(^"Companion") as Node2D
	var from := player.position
	if companion:
		companion.position = from + Vector2(-150, 60)
	await t.physics_frames(2)
	var swings := []
	var timer := t.get_tree().create_timer(3.0)
	Input.action_press(&"move_right")
	while timer.time_left > 0.0 and player.position.distance_to(from) < Player.STRIDE * 2.0:
		await t.frames(1)
		swings.append(player.get_swing())
	Input.action_release(&"move_right")
	var low: float = swings.min()
	var high: float = swings.max()
	var walked := player.position.distance_to(from)
	t.check(walked >= Player.STRIDE and high - low > 0.6, "[sailor] walking a stride or more swings the arms (%.2f .. %.2f; walked %.0f px)" % [low, high, walked])
	await t.screenshot("160_sailor_walking")
	await t.frames(30)
	t.check(is_zero_approx(snappedf(player.get_swing(), 0.05)), "[sailor] the arms come to rest after walking")


# --- Moored water ---------------------------------------------------------------------

func _test_moored_water() -> void:
	var deck := await _show(DECK, &"start")
	var life := deck.get_water_life()
	if not t.check(life != null, "[water] the deck has living water"):
		return
	t.check(life.visible and not life.is_underway_mode(), "[water] moored, in the illustrated art")
	t.check_eq(life.get_atmosphere(), WaterLife.ATMOSPHERE_URBAN, "[water] Copenhagen: the city harbour water")
	t.check(life.get_drifter_count() > 0 and life.get_drifter_count() <= WaterLife.MAX_DRIFTERS, "[water] a few drifting things (%d)" % life.get_drifter_count())
	t.check(life.get_lap_count() > 4, "[water] the water laps along the hull (%d places)" % life.get_lap_count())
	t.check(life.find_children("*", "CollisionObject2D", true, false).is_empty() and life.get_child_count() == 0, "[water] art only: no collision, no extra nodes")
	t.check(life.get_index() == deck.get_node("Surroundings/Water").get_index() + 1, "[water] drawn over the water, under the boat")
	var ripples_hidden := true
	for node in deck.get_node("Surroundings").get_children():
		if node is Line2D and String(node.name).begins_with("Ripple"):
			ripples_hidden = ripples_hidden and not (node as Line2D).visible
	t.check(ripples_hidden, "[water] the classic ripple strokes give way to the living water")
	GameSession.set_paused(true)
	await t.frames(10)
	t.check(life.is_processing() and life.visible, "[water] with the game clock paused the water still moves gently")
	GameSession.set_paused(false)
	await t.screenshot("161_moored_water_copenhagen")
	SettingsManager.set_art_style(SettingsManager.ART_CLASSIC)
	await t.frames(2)
	t.check(not life.visible, "[water] Classic art: the earlier static water")
	SettingsManager.set_art_style(SettingsManager.ART_ILLUSTRATED)
	await t.frames(2)
	var camera := deck.get_node("Camera2D") as Camera2D
	t.check(camera.zoom.is_equal_approx(deck.get_target_zoom()) and camera.zoom.x > 1.0, "[camera] moored: the harbour framing of the scene")


# --- All four boats --------------------------------------------------------------------

func _test_all_boats() -> void:
	for id in VesselCatalog.get_default().get_ids():
		GameSession.switch_vessel(id)
		var deck := await _show(DECK, &"from_boatyard")
		var visual := deck.get_node("Visual") as VesselVisual
		var sprites := visual.get_slot(&"DeckBase").is_sprite() and visual.get_slot(&"HullBase").is_sprite()
		t.check(sprites and visual.get_slot(&"DeckBase").get_sprite().texture.resource_path.contains("/%s/illustrated/deck/" % id),
			"[boats] %s: the illustrated teak deck" % id)
		t.check(deck.get_water_life() != null and deck.get_water_life().get_lap_count() > 4, "[boats] %s: the water laps along its hull" % id)
		await t.screenshot("162_deck_%s" % id)
		var cabin := await _show(CABIN, &"from_deck")
		var cabin_visual := cabin.get_node("Visual") as VesselVisual
		t.check(cabin_visual.get_slot(&"CabinBase").is_sprite() and cabin_visual.get_slot(&"FurnitureVisual").is_sprite(),
			"[boats] %s: the illustrated cabin" % id)
		t.check(cabin.get_hat_hook() != null, "[boats] %s: the hat hook" % id)
		await t.screenshot("163_cabin_%s" % id)
	GameSession.switch_vessel(VesselCatalog.STARTER_ID)


# --- Underway: wind-driven waves and the wider view -----------------------------------

func _test_underway() -> void:
	t.set_wind(270.0, 7.0)
	GameSession.plan_route_to(&"kiel")
	t.check_eq(GameSession.depart(), "", "(setup) underway to Kiel aboard the %s" % GameSession.get_vessel_definition().display_name)
	Simulation.advance(1800.0)
	var deck := await _show(DECK, &"start")
	var life := deck.get_water_life()
	var camera := deck.get_node("Camera2D") as Camera2D
	life.refresh()
	t.check(life.is_underway_mode() and life.get_drifter_count() == 0, "[waves] at sea: wave crests, no harbour drifters")
	var heading := Simulation.get_current_heading()
	var expected := Vector2.from_angle(deg_to_rad(270.0 + 180.0 - heading))
	t.check(life.get_wind_direction().dot(expected) > 0.999,
		"[waves] the crests follow the WeatherModel wind seen from the boat (heading %d°)" % roundi(heading))
	var light := life.get_wave_count()
	var framed := GameSession.get_vessel_definition().deck_scene.instantiate()
	var scene_zoom: Vector2 = (framed.get_node("Camera2D") as Camera2D).zoom
	framed.free()
	t.check(camera.zoom.is_equal_approx(scene_zoom * BoatArea.UNDERWAY_ZOOM_FACTOR), "[camera] underway the deck frames wider")
	await t.screenshot("164_sailing_light_wind")
	t.set_wind(270.0, 26.0)
	life.refresh()
	await t.frames(2)
	t.check(life.get_wave_count() > light and is_equal_approx(life.get_wind_kn(), 26.0),
		"[waves] stronger wind, more and livelier crests (%d -> %d)" % [light, life.get_wave_count()])
	t.check(life.get_wave_count() <= WaterLife.MAX_WAVES, "[waves] never more than %d crests" % WaterLife.MAX_WAVES)
	await t.screenshot("165_sailing_strong_wind")
	# The zoom eases from the harbour framing when the boat sets off.
	t.set_wind(270.0, 14.0)
	GameSession.end_session()
	app.start_new_game()
	await _settle()
	deck = await _show(DECK, &"start")
	camera = deck.get_node("Camera2D") as Camera2D
	var harbour := camera.zoom
	GameSession.plan_route_to(&"kiel")
	GameSession.depart()
	await t.frames(10)
	t.check(camera.zoom.x < harbour.x and camera.zoom.x > harbour.x * BoatArea.UNDERWAY_ZOOM_FACTOR,
		"[camera] leaving harbour, the view eases out (no jump)")
	await t.get_tree().create_timer(BoatArea.ZOOM_TRANSITION_S + 0.2).timeout
	t.check(camera.zoom.is_equal_approx(harbour * BoatArea.UNDERWAY_ZOOM_FACTOR), "[camera] and settles, modestly wider (x%.2f)" % BoatArea.UNDERWAY_ZOOM_FACTOR)
	t.check(is_equal_approx(camera.offset.y, 0.0), "[camera] the boat stays where it was framed")
	await t.screenshot("166_underway_framing")
	Simulation.advance(40.0 * 3600.0)
	await t.frames(2)
	if GameSession.is_underway():
		Simulation.advance(40.0 * 3600.0)
	await t.get_tree().create_timer(BoatArea.ZOOM_TRANSITION_S + 0.2).timeout
	deck = app.router.current_screen as BoatArea
	if deck and deck.has_node("Camera2D"):
		t.check(not GameSession.is_underway() and (deck.get_node("Camera2D") as Camera2D).zoom.is_equal_approx(harbour),
			"[camera] arriving, the harbour framing returns")
	t.use_calm_wind()
