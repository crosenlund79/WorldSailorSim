extends RefCounted
## Iteration 18 (PET, ANCH-9 to ANCH-11, LIGHT-3):
##   - the companion follows the captain up on deck and back down while the
##     boat is moored or safely at anchor, after a natural delay; it rests at
##     safe places worked out for each boat (inside the lifeline, clear of
##     fittings, away from the helm and stations); every frame of its walks
##     stays aboard; it goes below when the boat sets off, the anchor comes up
##     or the weather turns, and stays below underway; its place is saved;
##   - at anchor: the black ball in the forward rigging, the rode and the
##     buoy; none of them moored, underway or merely waiting at an anchorage;
##   - lights at night: red, green and the stern light underway only; the
##     white anchor light at anchor only; neither when moored.

const APP_SCENE := preload("res://src/app/app.tscn")
const BOATS: Array[StringName] = [&"arctic_wanderer_26", &"starling_33", &"petrel_36", &"halcyon_40"]
const DECK := SessionState.AREA_EXTERIOR
const CABIN := SessionState.AREA_INTERIOR
const MAY_1 := 1777593600.0

var t: Node
var app: Node


func run(runner: Node) -> void:
	t = runner
	Simulation.auto_advance = false
	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	app.start_new_game()
	await _settle()
	t.set_wind(200.0, 8.0)
	await _test_every_boat()
	await _test_follow_and_save()
	await _test_underway_and_anchor()
	Simulation.auto_advance = true
	app.queue_free()
	await t.frames(2)
	GameSession.end_session()
	t.use_calm_wind()


func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)


func _show(area: StringName, spawn := &"start") -> BoatArea:
	app.modals.clear()
	GameSession.enter_boat_area(area, spawn)
	app._show_current_boat_area()
	await _settle()
	return app.router.current_screen as BoatArea


func _board(id: StringName) -> void:
	var state := GameSession.get_state_snapshot()
	state.vessel_id = id
	state.companion.area = CompanionState.AREA_CABIN
	GameSession.replace_state(state)


func _set_time(time: float) -> void:
	var state := GameSession.get_state_snapshot()
	state.game_time = time
	GameSession.replace_state(state)


## Lets the companion follow (the app's own timing, run on).
func _follow(seconds := 9.0) -> void:
	var step := 0.25
	var left := seconds
	while left > 0.0:
		app._update_companion_follow(step)
		left -= step
		await t.frames(1)


## Lets a walk finish, checking every frame that it stays aboard.
func _walk_out(deck: BoatArea, companion: ShipCompanion) -> Array:
	var unsafe := 0
	var frames := 0
	var spots := deck.get_node("Layout/DeckCompanionSpots") as DeckCompanionSpots
	var started := Time.get_ticks_msec()
	while companion.is_walking() and Time.get_ticks_msec() - started < 30000:
		await t.frames(1)
		# I024: it walks at its stride's own (slower, real) pace; run its walk on
		# a little faster, still checking every step.
		companion._process(0.05)
		frames += 1
		if companion.visible and not spots.is_safe(companion.position, false):
			unsafe += 1
	return [frames, unsafe]


func _test_every_boat() -> void:
	for id in BOATS:
		_board(id)
		var deck := await _show(DECK)
		var spots := deck.get_node_or_null("Layout/DeckCompanionSpots") as DeckCompanionSpots
		var companion := deck.get_deck_companion()
		if not t.check(spots != null and companion != null, "[pet] %s: the deck has places for the companion" % id):
			continue
		var helm := (deck.get_node("Layout/Stations/Helm") as Node2D).position
		var safe := true
		for i in 3:
			var p := spots.get_spot(i)
			safe = safe and spots.is_safe(p) and spots.is_aboard(p) and p.distance_to(helm) >= DeckCompanionSpots.HELM_CLEARANCE
		t.check(safe, "[pet] %s: three resting places, aboard (not over the water, not on the pontoon), clear of fittings and the helm" % id)
		t.check(spots.get_spot(0).x < spots.get_spot(1).x and spots.get_spot(1).x < spots.get_spot(2).x, "[pet] %s: aft, amidships and forward" % id)
		t.check(not companion.visible, "[pet] %s: at first it is below" % id)
		await _follow()
		t.check(GameSession.get_companion().area == CompanionState.AREA_DECK and companion.visible, "[pet] %s: moored, it comes up on deck after the captain" % id)
		var walk := await _walk_out(deck, companion)
		t.check(walk[1] == 0 and companion.position.is_equal_approx(spots.get_spot(GameSession.get_companion().deck_spot)),
			"[pet] %s: it walks up from the companionway to its place, every frame aboard (%d frames, %d off, at %s for %s)" % [id, walk[0], walk[1], companion.position, spots.get_spot(GameSession.get_companion().deck_spot)])
		if id == &"starling_33":
			app.toasts.clear()
			await t.frames(2)
			await t.screenshot("18_pet_on_deck_moored")
		var cabin := await _show(CABIN, &"from_deck")
		await _follow()
		var below := cabin.find_child("Companion", true, false) as ShipCompanion
		t.check(GameSession.get_companion().area == CompanionState.AREA_CABIN and below != null and below.visible,
			"[pet] %s: the captain goes below; a little later so does the companion" % id)
		GameSession.set_companion_area(CompanionState.AREA_CABIN)
	_board(&"starling_33")


func _test_follow_and_save() -> void:
	var deck := await _show(DECK)
	await _follow(1.0)
	t.check(GameSession.get_companion().area == CompanionState.AREA_CABIN, "[pet] not at once: it takes a moment to follow")
	await _follow()
	t.check(GameSession.get_companion().area == CompanionState.AREA_DECK, "(setup) on deck")
	await _walk_out(deck, deck.get_deck_companion())
	# It stays on deck through a save and load.
	t.check_eq(SaveManager.save_to_slot(3, GameSession.get_state_snapshot()), OK, "(setup) saved with the companion on deck")
	GameSession.set_companion_area(CompanionState.AREA_CABIN)
	app.load_slot(3)
	await _settle()
	var after := app.router.current_screen as BoatArea
	var companion := after.get_deck_companion() if after else null
	t.check(GameSession.get_companion().area == CompanionState.AREA_DECK and companion != null and companion.visible and not companion.is_walking(),
		"[save] loaded with the companion on deck, at its place")
	SaveManager.delete_slot(3)
	# Petting on deck works as below.
	t.check(companion != null and companion.interactable.enabled, "[pet] on deck it can be petted")
	# Casting off: it goes below by itself.
	GameSession.plan_route_to(&"malmo")
	t.check_eq(GameSession.depart(), "", "(setup) depart for Malmö")
	t.check_eq(GameSession.get_companion().area, CompanionState.AREA_CABIN, "[safe] casting off, the companion goes below")
	var walk := await _walk_out(after, companion)
	t.check(not companion.visible and walk[1] == 0, "[safe] it walks to the companionway and down, never over the side (%d frames, %d off, visible %s, at %s, entry %s)" % [walk[0], walk[1], companion.visible, companion.position, after.get_node("Layout/DeckCompanionSpots").get_entry()])
	await _follow()
	t.check_eq(GameSession.get_companion().area, CompanionState.AREA_CABIN, "[safe] underway it stays below while the captain sails")


func _test_underway_and_anchor() -> void:
	var near := false
	for i in 120:
		Simulation.advance(300.0)
		if GameSession.evaluate_anchorage().ok:
			near = true
			break
	if not t.check(near and GameSession.drop_anchor(5, 0.9).error == "", "(setup) at anchor"):
		return
	# By day: the ball, the rode and the buoy.
	var noon := MAY_1 + (12.0 - GameSession.get_vessel_position().x / 15.0) * 3600.0
	_set_time(noon)
	var deck := await _show(DECK)
	var signals := deck.get_anchor_signals()
	t.check(signals != null and signals.visible, "[ball] at anchor the anchor ball, rode and buoy show")
	var rig := deck.get_node("SailRig") as SailRig
	var ball := signals.get_ball_position()
	t.check(ball.x > rig.mast.x and ball.x < signals.bow.x, "[ball] the ball hangs in the forward rigging, between the mast and the bow")
	t.check(signals.get_buoy_position().x > signals.bow.x, "[buoy] the buoy floats ahead of the bow, where the rode goes")
	var lamps := deck.get_lighting().get_lit_lamps()
	t.check(lamps.is_empty(), "[lights] by day no lamps")
	await _follow()
	t.check(GameSession.get_companion().area == CompanionState.AREA_DECK, "[pet] at anchor in fair weather the companion comes up too")
	await _walk_out(deck, deck.get_deck_companion())
	app.toasts.clear()
	await t.frames(2)
	await t.screenshot("18_anchored_day_ball_buoy_pet")
	# At night: the white anchor light only.
	var night := noon + 11.0 * 3600.0
	_set_time(night)
	deck = await _show(DECK)
	await t.frames(3)
	lamps = deck.get_lighting().get_lit_lamps()
	t.check(lamps.size() == 1 and lamps[0].when == "anchor" and lamps[0].colour.is_equal_approx(BoatLighting.NAV_WHITE),
		"[lights] at night at anchor: the white anchor light, no red or green (%s)" % [lamps])
	await t.screenshot("18_anchored_night_light")
	# Strong wind: the companion goes below.
	t.set_wind(200.0, 26.0)
	Simulation.advance(600.0)
	t.check_eq(GameSession.get_companion().area, CompanionState.AREA_CABIN, "[safe] when the wind gets up, the companion goes below")
	t.set_wind(200.0, 8.0)
	# Weighing anchor: signals go; underway at night the navigation lights.
	t.check_eq(GameSession.raise_anchor(), "", "(setup) anchor up")
	Simulation.advance(300.0)
	await t.frames(3)
	t.check(not deck.get_anchor_signals().visible, "[ball] underway: no ball, no buoy")
	lamps = deck.get_lighting().get_lit_lamps()
	var whens := lamps.map(func(l: Dictionary) -> String: return l.when)
	var red := lamps.filter(func(l: Dictionary) -> bool: return l.colour.is_equal_approx(BoatLighting.NAV_RED))
	var green := lamps.filter(func(l: Dictionary) -> bool: return l.colour.is_equal_approx(BoatLighting.NAV_GREEN))
	var bounds := deck.get_lighting().boat_bounds()
	t.check(lamps.size() == 3 and whens.all(func(w: String) -> bool: return w == "underway"),
		"[lights] at night underway: three navigation lights, no anchor light (%s)" % [whens])
	t.check(red.size() == 1 and green.size() == 1 and red[0].at.y < bounds.get_center().y and green[0].at.y > bounds.get_center().y
		and red[0].at.x > bounds.position.x + bounds.size.x * 0.7, "[lights] red to port and green to starboard, at the bow")
	var spots := deck.get_node("Layout/DeckCompanionSpots") as DeckCompanionSpots
	t.check(red.size() == 1 and green.size() == 1 and spots.is_aboard(red[0].at) and spots.is_aboard(green[0].at),
		"[lights] the side lights sit on the hull, not out over the water")
	app.toasts.clear()
	app.modals.clear()
	app.hud.hide_warning()
	await t.frames(3)
	await t.screenshot("18_underway_navigation_lights")
	# All eight orientations: on screen, red stays to port and green to
	# starboard of the heading, both ahead of the stern light.
	var white := lamps.filter(func(l: Dictionary) -> bool: return l.colour.is_equal_approx(BoatLighting.NAV_WHITE))
	var sides_ok := red.size() == 1 and green.size() == 1 and white.size() == 1
	for k in 8:
		deck.view_heading_override = k * 45.0
		await t.wait_until(func() -> bool: return absf(angle_difference((deck.get_node("Camera2D") as Camera2D).rotation, deck.get_target_rotation())) < 0.01, 3.0)
		await t.frames(2)
		if not sides_ok:
			break
		var to_screen := deck.get_global_transform_with_canvas()
		var r: Vector2 = to_screen * red[0].at
		var g: Vector2 = to_screen * green[0].at
		var w: Vector2 = to_screen * white[0].at
		var ahead := Vector2(sin(deg_to_rad(k * 45.0)), -cos(deg_to_rad(k * 45.0)))
		var port := Vector2(ahead.y, -ahead.x)
		sides_ok = (r - g).dot(port) > 0.0 and (r - w).dot(ahead) > 0.0 and (g - w).dot(ahead) > 0.0
	deck.view_heading_override = NAN
	t.check(sides_ok, "[lights] in all eight orientations red is to port, green to starboard, both forward of the stern light")
	# Waiting at an anchorage (stopped, not anchored): no anchor signals.
	var voyage := GameSession.get_voyage()
	voyage.holding_at = -1
	# Moored at night: neither navigation nor anchor lights.
	var state := GameSession.get_state_snapshot()
	state.location_id = &"copenhagen"
	state.vessel_status = SessionState.STATUS_MOORED
	state.vessel_position = PortCatalog.get_default().get_port(&"copenhagen").get_geo_position()
	state.voyage = null
	state.anchor.active = false
	GameSession.replace_state(state)
	_set_time(night)
	deck = await _show(DECK)
	await t.frames(3)
	t.check(deck.get_lighting().get_lit_lamps().is_empty() and not deck.get_anchor_signals().visible,
		"[lights] moored at night: no navigation or anchor lights, no ball (the harbour lights the quay)")
