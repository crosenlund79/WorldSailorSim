extends RefCounted
## I026 stage 02, living harbours: the quay (HarbourFront) up the pontoon's
## walkway, a building for every business the harbour has (QuayLayout),
## opening hours on the harbour's own clock (BusinessHours) with a wait for
## opening time and the office's after-hours hatch, the menus in their
## shop-counter frames (ShopCounter), the townsfolk (HarbourLife), the café,
## the noticeboard and the harbour office (HarbourNotes), and saving on the
## quay without a new save field. Focused checks: what a player would notice.

const APP_SCENE := preload("res://src/app/app.tscn")
const W := preload("res://tests/helpers/walkability.gd")

var t: Node
var app: Node


func run(runner: Node) -> void:
	t = runner
	Simulation.auto_advance = false
	t.use_calm_wind()
	_test_hours_data()
	_test_layouts()
	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	app.start_new_game()
	await _settle()
	await _test_walkway()
	await _test_quay()
	await _test_doors_and_counters()
	await _test_closed_and_waiting()
	await _test_hatch()
	await _test_cafe()
	await _test_people()
	await _test_wheel_and_keys()
	await _test_layout()
	await _test_save_on_the_quay()
	await _test_walk_back_down()
	Simulation.auto_advance = true
	app.queue_free()
	await t.frames(2)
	GameSession.end_session()
	t.use_calm_wind()


func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)


## Moored in `port_id` at local solar hour `hour` on local weekday `weekday`
## (0 = Sunday).
func _moor_at(port_id: StringName, hour: float, weekday := 3) -> void:
	var state := GameSession.get_state_snapshot()
	state.location_id = port_id
	state.vessel_status = SessionState.STATUS_MOORED
	state.vessel_position = PortCatalog.get_default().get_port(port_id).get_geo_position()
	state.voyage = null
	var lon := state.vessel_position.x
	var day_start := floorf(state.game_time / 86400.0) * 86400.0
	state.game_time = day_start + fposmod(hour - lon / 15.0, 24.0) * 3600.0
	while BusinessHours.local_weekday(port_id, state.game_time) != weekday:
		state.game_time += 86400.0
	GameSession.replace_state(state)


func _deck() -> BoatArea:
	app.modals.clear()
	GameSession.enter_boat_area(SessionState.AREA_EXTERIOR, &"from_boatyard")
	app._show_current_boat_area()
	await _settle()
	return app.router.current_screen as BoatArea


## Up the walkway (through the deck's own station).
func _quay() -> HarbourFront:
	var deck := await _deck()
	deck.get_walkway().interact(deck.player)
	await _settle()
	return app.router.current_screen as HarbourFront


func _toast_contains(text: String) -> bool:
	for message in app.toasts.get_messages():
		if text in message:
			return true
	return false


# --- Data ------------------------------------------------------------------------

func _test_hours_data() -> void:
	var types := BusinessHours.get_types()
	var all := true
	for business in QuayLayout.BUSINESSES:
		all = all and business in types
	t.check(all, "[hours] every business on the quay has opening hours in the data (%s)" % [types])
	var cafe := BusinessHours.hours(QuayLayout.CAFE, &"svendborg")
	var loft := BusinessHours.hours(QuayLayout.SAIL_LOFT, &"svendborg")
	t.check(cafe.x < loft.x, "[hours] the café opens earlier than the sail loft (%s vs %s)" % [cafe, loft])
	var nordic := BusinessHours.hours(QuayLayout.GROCERY, &"svendborg")
	var med := BusinessHours.hours(QuayLayout.GROCERY, &"naples")
	t.check(med.y > nordic.y, "[hours] the region nudges the hours: a Mediterranean grocery closes later (%s vs %s)" % [med, nordic])
	var small := BusinessHours.hours(QuayLayout.CAFE, &"lohals")
	var major := BusinessHours.hours(QuayLayout.CAFE, &"copenhagen")
	t.check(small.y - small.x < major.y - major.x, "[hours] a small harbour keeps shorter hours than a major one (%s vs %s)" % [small, major])
	# Sunday at the yard, a weekday at the yard.
	var lon := BusinessHours.longitude_of(&"copenhagen")
	var t0 := 1778000000.0
	var sunday := t0
	while BusinessHours.local_weekday(&"copenhagen", sunday) != 0:
		sunday += 86400.0
	sunday = floorf((sunday + lon / 15.0 * 3600.0) / 86400.0) * 86400.0 - lon / 15.0 * 3600.0 + 11.0 * 3600.0
	t.check(not BusinessHours.is_open(QuayLayout.BOATYARD, &"copenhagen", sunday) and BusinessHours.is_open(QuayLayout.CAFE, &"copenhagen", sunday),
		"[hours] on Sunday the boatyard rests while the café is open")
	var monday := BusinessHours.next_opening(QuayLayout.BOATYARD, &"copenhagen", sunday)
	t.check(monday > sunday and BusinessHours.is_open(QuayLayout.BOATYARD, &"copenhagen", monday)
		and BusinessHours.local_weekday(&"copenhagen", monday) == 1, "[hours] its next opening is Monday morning, and it is open then")
	t.check(BusinessHours.status_text(QuayLayout.BOATYARD, &"copenhagen", sunday).contains(Loc.weekday(1)),
		"[hours] the door says when: '%s'" % BusinessHours.status_text(QuayLayout.BOATYARD, &"copenhagen", sunday))
	var night := sunday + 12.0 * 3600.0
	t.check(BusinessHours.is_open(QuayLayout.NOTICEBOARD, &"copenhagen", night), "[hours] the noticeboard is always there")
	# Local solar time: the same UTC moment is morning in the east and night in the west.
	t.check(absf(BusinessHours.local_hours(&"copenhagen", t0) - Daylight.local_solar_hours(lon, t0)) < 0.001,
		"[hours] hours are on the harbour's local solar time (Daylight)")


func _test_layouts() -> void:
	var cph := QuayLayout.build(&"copenhagen")
	var expected: Array[StringName] = [QuayLayout.BOATYARD, QuayLayout.SAIL_LOFT, QuayLayout.CHANDLERY, QuayLayout.HARBOUR_OFFICE,
		QuayLayout.CAFE, QuayLayout.GROCERY, QuayLayout.FISHMONGER]
	t.check(cph.get_businesses() == expected, "[layout] Copenhagen: yard, sail loft, chandlery, office, café, grocery, fishmonger in quay order (%s)" % [cph.get_businesses()])
	t.check(cph.lift != Vector2.ZERO and not cph.get_front(QuayLayout.LANE).is_empty(),
		"[layout] Copenhagen hauls out (a travel lift) and has a lane into town (Go Ashore)")
	var lohals := QuayLayout.build(&"lohals")
	t.check(not lohals.has_business(QuayLayout.BOATYARD) and not lohals.has_business(QuayLayout.CHANDLERY)
		and not lohals.has_business(QuayLayout.SAIL_LOFT) and lohals.has_business(QuayLayout.GROCERY) and lohals.has_business(QuayLayout.FISHMONGER),
		"[layout] Lohals (no boatyard): no yard, chandlery or sail loft; the grocery and the fishmonger are there (%s)" % [lohals.get_businesses()])
	t.check(lohals.has_business(QuayLayout.CAFE) and lohals.has_business(QuayLayout.HARBOUR_OFFICE) and lohals.lift == Vector2.ZERO,
		"[layout] every harbour has its café and harbour office; no travel lift without a haul-out yard")
	# The trades follow their parent exactly (HarbourTrades) in every harbour.
	var mismatch := []
	var overlaps := []
	for port in PortCatalog.get_default().ports:
		var facilities := HarbourFacilities.for_port(port.id)
		var layout := QuayLayout.build(port.id)
		for pair in [[QuayLayout.BOATYARD, HarbourFacilities.BOATYARD], [QuayLayout.CHANDLERY, HarbourFacilities.CHANDLERY],
				[QuayLayout.SAIL_LOFT, HarbourFacilities.SAILMAKER], [QuayLayout.GROCERY, HarbourFacilities.GROCERY],
				[QuayLayout.FISHMONGER, HarbourFacilities.FISHMONGER], [QuayLayout.LANE, HarbourFacilities.GO_ASHORE]]:
			if layout.has_business(pair[0]) != facilities.has(pair[1]) and not (pair[0] == QuayLayout.LANE and layout.get_front(QuayLayout.LANE).is_empty() == not facilities.has(pair[1])):
				mismatch.append("%s:%s" % [port.id, pair[0]])
		for i in range(1, layout.fronts.size()):
			if float(layout.fronts[i].x0) < float(layout.fronts[i - 1].x1) - 0.5:
				overlaps.append(String(port.id))
	t.check(mismatch.is_empty(), "[layout] in every harbour a storefront stands exactly where the harbour offers the service (%s)" % [mismatch.slice(0, 6)])
	t.check(overlaps.is_empty(), "[layout] no two buildings overlap on any quay (%s)" % [overlaps.slice(0, 6)])
	var again := QuayLayout.build(&"copenhagen")
	t.check(again.fronts == cph.fronts and again.cafe_seats == cph.cafe_seats, "[layout] the same harbour always has the same quay")
	t.check(not cph.is_in_the_way(cph.door_station(QuayLayout.CAFE) + Vector2(0, 200)) and cph.is_in_the_way(Vector2(0, QuayLayout.EDGE_Y - 40))
		and cph.is_in_the_way(Vector2(float(cph.get_front(QuayLayout.CHANDLERY).door), 40.0)),
		"[layout] the doorways and the walkway's head count as in the way; the promenade does not")


# --- The walkway on the pontoon --------------------------------------------------------

func _test_walkway() -> void:
	_moor_at(&"copenhagen", 11.0)
	for id in VesselCatalog.get_default().get_ids():
		t.board(id)
		var deck := await _deck()
		var shore := deck.get_shore_access()
		var walkway := deck.get_walkway()
		var cells := W.walkable_cells(deck, deck.get_spawn_position(&"start"))
		t.check(walkway != null and walkway.enabled and walkway.visible and walkway.position.y > shore.get_rail_y()
			and not W.use_points(walkway, cells).is_empty(), "[walkway] %s: the walkway stands on the pontoon and can be walked to" % id)
		var old_ok := true
		for facility in [HarbourFacilities.GROCERY, HarbourFacilities.BOATYARD, HarbourFacilities.GO_ASHORE]:
			var station := deck.get_shore_station(facility)
			old_ok = old_ok and (station == null or (not station.enabled and not station.visible and not station.monitorable))
		t.check(old_ok, "[walkway] %s: the businesses have left the pontoon (no service stations there, no invisible targets)" % id)
		var dock := deck.get_dock_encounter_scene()
		var box_x := shore.get_plank_x() + DockEncounterScene.BOX_OFFSET
		t.check(absf(walkway.position.x - box_x) > 120.0 and absf(walkway.position.x - (shore.get_plank_x() - DockEncounterScene.BOX_OFFSET)) > 120.0,
			"[walkway] %s: clear of the dock animal's box (either side of the plank)" % id)
		var spots_clear := true
		for i in ShipCompanion.SHORE_OFFSETS.size():
			spots_clear = spots_clear and ShipCompanion.get_shore_spot(shore, i).distance_to(walkway.position) > 80.0
		t.check(spots_clear and dock != null, "[walkway] %s: and of the companions' places on the pontoon" % id)
	t.board(VesselCatalog.STARTER_ID)
	var deck := await _deck()
	t.check(deck.get_harbour_dressing().get_sign_ids() == ([BoatArea.WALKWAY_ID] as Array[StringName]),
		"[walkway] one marina sign on the pontoon now: To the quay (%s)" % [deck.get_harbour_dressing().get_sign_ids()])
	var walkway := deck.get_walkway()
	deck.player.position = walkway.position + Vector2(0, -26)
	await t.physics_frames(4)
	t.check(deck.player.get_focused_interactable() == walkway and app.hud.get_prompt() == "To the quay" and walkway.highlight_outline.size() >= 3,
		"[walkway] walking up to it: its sign lights up, 'To the quay' (%s)" % app.hud.get_prompt())
	await t.screenshot("i026_01_walkway")
	await t.press_action(&"interact")
	await _settle()
	var front := app.router.current_screen as HarbourFront
	t.check(front != null and front.port_id == &"copenhagen", "[walkway] E takes the Captain up to the quay")
	t.check(GameSession.get_boat_area() == SessionState.AREA_EXTERIOR and GameSession.get_player_position().is_equal_approx(deck.get_walkway_return_point()) \
		if is_instance_valid(deck) else GameSession.get_boat_area() == SessionState.AREA_EXTERIOR,
		"[walkway] in the game state the Captain is still on deck, on the pontoon by the walkway")
	t.check(app._hud_layer.visible and app.hud.get_node("%AreaLabel").text == "The quay", "[walkway] the HUD with the clock shows, the place named 'The quay'")


# --- The quay ----------------------------------------------------------------------

func _quay_cells(front: HarbourFront, from: Vector2) -> Array[Vector2]:
	var space := front.get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = W.PLAYER_RADIUS
	query.shape = circle
	query.collision_mask = front.player.collision_mask
	query.exclude = [front.player.get_rid()]
	var grid := 20.0
	var cells: Array[Vector2] = []
	var seen := {from: true}
	var queue: Array[Vector2] = [from]
	var bounds := Rect2(front.layout.left - 40.0, -40.0, front.layout.right - front.layout.left + 80.0, QuayLayout.EDGE_Y + 140.0)
	while not queue.is_empty():
		var p: Vector2 = queue.pop_back()
		cells.append(p)
		for step in [Vector2(grid, 0), Vector2(-grid, 0), Vector2(0, grid), Vector2(0, -grid)]:
			var q: Vector2 = p + step
			if seen.has(q) or not bounds.has_point(q):
				continue
			seen[q] = true
			query.transform = Transform2D(0.0, front.to_global(q))
			if space.intersect_shape(query, 1).is_empty():
				queue.append(q)
	return cells


func _test_quay() -> void:
	var front := app.router.current_screen as HarbourFront
	if not t.check(front != null, "[quay] the quay is on screen"):
		return
	var layout := front.get_layout()
	var drawn := []
	for business in layout.get_businesses():
		drawn.append(front.get_storefront(business) != null and front.get_station(business) != null)
	t.check(not false in drawn and drawn.size() == 7, "[quay] Copenhagen: a storefront and a door for each of its seven businesses")
	t.check(front.get_station(HarbourFront.HATCH) != null and front.get_station(QuayLayout.NOTICEBOARD) != null
		and front.get_station(QuayLayout.LANE) != null and front.get_station(HarbourFront.TRAVEL_LIFT) != null,
		"[quay] and the office hatch, the noticeboard, the lane into town and the travel lift")
	var cells := _quay_cells(front, layout.arrival_point())
	var unreachable := []
	for place: StringName in front.stations:
		if W.use_points(front.stations[place], cells).is_empty():
			unreachable.append(place)
	t.check(unreachable.is_empty(), "[quay] every door and station can be walked to from the walkway (%s)" % [unreachable])
	var highlights := true
	for business in layout.get_businesses():
		highlights = highlights and front.get_station(business).highlight_outline.size() >= 3
	t.check(highlights, "[quay] each door lights up its own storefront (no circles)")
	front.player.position = layout.door_station(QuayLayout.BOATYARD) + Vector2(0, 8)
	await t.physics_frames(4)
	t.check(front.player.get_focused_interactable() == front.get_station(QuayLayout.BOATYARD) and app.hud.get_prompt().begins_with("Boatyard · open"),
		"[quay] at the boatyard's door: '%s'" % app.hud.get_prompt())
	await t.screenshot("i026_02_quay_boatyard")
	# True scale: a door is about a metre wide, the Captain about 0.4 m.
	t.check(QuayLayout.DOOR_HALF * 2.0 > 2.0 * Player.RADIUS * 2.0 and QuayLayout.DOOR_HALF * 2.0 < 140.0,
		"[quay] at true scale: a door about a metre wide beside the Captain")
	var lit := front.get_storefront(QuayLayout.CHANDLERY)
	t.check(lit.is_open and lit.hours_plate.contains(BusinessHours.format_hour(BusinessHours.hours(QuayLayout.CHANDLERY, &"copenhagen").x)),
		"[quay] the chandlery's door shows it open, with its hours on the plate (%s)" % lit.hours_plate)


func _test_doors_and_counters() -> void:
	var front := app.router.current_screen as HarbourFront
	var cases := [[QuayLayout.CHANDLERY, ChandleryMenu], [QuayLayout.SAIL_LOFT, SailmakerMenu], [QuayLayout.GROCERY, GroceryMenu],
		[QuayLayout.FISHMONGER, FishmongerMenu], [QuayLayout.BOATYARD, BoatyardMenu], [QuayLayout.CAFE, CafeMenu],
		[QuayLayout.HARBOUR_OFFICE, HarbourOfficeMenu], [QuayLayout.NOTICEBOARD, NoticeboardMenu], [QuayLayout.LANE, GoAshoreMenu],
		[HarbourFront.TRAVEL_LIFT, BoatCareMenu]]
	for case in cases:
		app.modals.clear()
		await t.frames(1)
		var station: Interactable = front.get_station(case[0])
		front.player.position = station.position + Vector2(0, 6)
		await t.physics_frames(3)
		await t.press_action(&"interact")
		await t.frames(3)
		var top: Control = app.modals.get_top()
		var frame := top.get_node_or_null(^"ShopCounter") as ShopCounter if top else null
		t.check(top != null and is_instance_of(top, case[1]) and frame != null and get_tree_paused(),
			"[counter] %s: E opens its own menu in the shop's counter frame, the game paused (%s)" % [case[0], top])
		if case[0] == QuayLayout.CHANDLERY:
			t.check(frame.sign_text == "Chandlery" and frame.get_sign_rect().has_area()
				and not frame.get_sign_rect().intersects(Rect2(top.find_child("Panel", true, false).global_position, top.find_child("Panel", true, false).size)),
				"[counter] the chandlery's sign hangs above its panel, clear of it")
			await t.screenshot("i026_03_chandlery_counter")
		if case[0] == QuayLayout.GROCERY:
			t.check(top.find_child("FishmongerButton", true, false) == null, "[counter] the grocery no longer leads to the fishmonger (it has its own stall)")
		if case[0] == QuayLayout.BOATYARD:
			var yard := top as BoatyardMenu
			t.check(yard.find_child("GroceryButton", true, false) == null and yard.find_child("ChandleryButton", true, false) == null
				and yard.find_child("SailmakerButton", true, false) == null and yard.find_child("CareButton", true, false) != null,
				"[counter] the boatyard is no longer a hub: Boat care stays, the grocery, chandlery and sail loft have their own doors")
			await t.click(yard.find_child("CareButton", true, false))
			await t.frames(3)
			t.check(app.modals.get_top() is BoatCareMenu and app.modals.get_top().has_node(^"ShopCounter"),
				"[counter] Boat care opens on top, in the yard's frame too")
		top = app.modals.get_top()
		top.handle_back()
		await t.frames(2)
	app.modals.clear()
	await t.frames(2)
	# The cabin's provisions locker still reaches the grocery (no frame there).
	t.check(not get_tree_paused(), "[counter] closing the menus returns to the quay")


func get_tree_paused() -> bool:
	return t.get_tree().paused


func _test_closed_and_waiting() -> void:
	var opens := BusinessHours.hours(QuayLayout.CHANDLERY, &"copenhagen").x
	_moor_at(&"copenhagen", opens - 1.5)
	var front := await _quay()
	var station := front.get_station(QuayLayout.CHANDLERY)
	front.refresh()
	t.check(not front.get_storefront(QuayLayout.CHANDLERY).is_open and station.prompt.contains("closed")
		and station.prompt.contains(BusinessHours.format_hour(opens)), "[closed] early morning the chandlery is shut: '%s'" % station.prompt)
	t.check(front.get_storefront(QuayLayout.CAFE).is_open, "[closed] while the café is already open")
	front.player.position = station.position + Vector2(0, 6)
	await t.physics_frames(3)
	await t.press_action(&"interact")
	await t.frames(3)
	var dialog := app.modals.get_top() as ConfirmDialog
	t.check(dialog != null, "[closed] E at a closed door offers to wait until it opens")
	await t.screenshot("i026_04_closed_wait")
	var before := GameSession.get_game_time()
	if dialog:
		await t.click(dialog.find_child("ConfirmButton", true, false))
	await t.wait_until(func() -> bool: return app.modals.is_empty() and not is_instance_valid(app.time_passage), 5.0)
	await t.frames(3)
	t.check(GameSession.get_game_time() > before + 3600.0 and BusinessHours.is_open(QuayLayout.CHANDLERY, &"copenhagen", GameSession.get_game_time()),
		"[closed] waiting lets the time pass on the one clock until it opens (%s)" % Simulation.format_game_time(GameSession.get_game_time()))
	t.check(app.router.current_screen == front and front.get_storefront(QuayLayout.CHANDLERY).is_open, "[closed] still on the quay, the door now open")


func _test_hatch() -> void:
	_moor_at(&"copenhagen", 23.0)
	var front := await _quay()
	t.check(not BusinessHours.is_open(QuayLayout.HARBOUR_OFFICE, &"copenhagen", GameSession.get_game_time()), "[hatch] at night the office is shut")
	GameSession.set_provisions_for_testing(4.0)
	GameSession.set_condition_for_testing(40.0)
	var hatch := front.get_station(HarbourFront.HATCH)
	front.player.position = hatch.position + Vector2(0, 6)
	await t.physics_frames(3)
	await t.press_action(&"interact")
	await t.frames(3)
	var office := app.modals.get_top() as HarbourOfficeMenu
	if not t.check(office != null and office.hatch and office.has_node(^"ShopCounter"), "[hatch] the after-hours hatch answers at any hour"):
		return
	await t.screenshot("i026_05_hatch")
	var funds := GameSession.get_funds()
	var price := GameSession.get_provisions_price()
	await t.click(office.get_food_button())
	await t.frames(2)
	t.check(GameSession.get_food_days() >= 14.0 and GameSession.get_funds() == funds - price, "[hatch] food and water for the boat, at the grocery's price")
	t.check(office.get_repair_button().visible and not office.get_repair_button().disabled, "[hatch] a damaged hull: an emergency repair is offered")
	var time := GameSession.get_game_time()
	await t.click(office.get_repair_button())
	await t.wait_until(func() -> bool: return not is_instance_valid(app.time_passage) and app.modals.is_empty(), 5.0)
	t.check(GameSession.get_condition() >= 100.0 and GameSession.get_game_time() > time, "[hatch] the hull is repaired and the yard's time passes")
	GameSession.set_provisions_for_testing(14.0)


func _test_cafe() -> void:
	_moor_at(&"copenhagen", 13.0)
	var front := await _quay()
	var cafe := front.get_station(QuayLayout.CAFE)
	front.player.position = cafe.position + Vector2(0, 6)
	await t.physics_frames(3)
	await t.press_action(&"interact")
	await t.frames(3)
	var menu := app.modals.get_top() as CafeMenu
	if not t.check(menu != null, "[café] the café's counter opens"):
		return
	var funds := GameSession.get_funds()
	var price := GameSession.cafe_coffee_price()
	t.check(price > 0 and price <= 10, "[café] a coffee costs a little (%s)" % GameSession.format_money(price))
	await t.click(menu.get_order_button())
	await t.frames(3)
	t.check(GameSession.get_funds() == funds - price and front.is_seated() and front.player.cafe_mug and app.modals.is_empty(),
		"[café] ordering pays, and the Captain sits at a terrace table with a mug")
	t.check(not GameSession.is_carrying_coffee(), "[café] the café's mug is not the boat's (nothing in the save changes)")
	var time := GameSession.get_game_time()
	Simulation.tick(2.0)
	t.check(GameSession.get_game_time() > time and front.is_seated() and not t.get_tree().paused, "[café] time passes normally while seated")
	var people := front.life.get_people().filter(func(p: Node) -> bool: return p.is_seated())
	t.check(not people.is_empty(), "[café] a few customers sit at the other tables (%d)" % people.size())
	var seat_taken := false
	for person in front.life.get_people():
		seat_taken = seat_taken or int(person.entry.get("seat", -1)) == front.seat_index
	t.check(not seat_taken, "[café] nobody else sits in the Captain's chair")
	await t.screenshot("i026_06_cafe")
	await t.press_action(&"move_down")
	await t.frames(2)
	t.check(not front.is_seated() and not front.player.cafe_mug and front.player.input_enabled, "[café] a movement key stands the Captain up again")
	# A companion ashore comes along and rests by the table.
	app.leave_quay()
	await _settle()
	app.start_new_game(&"cat", Difficulty.STANDARD, "Kiwi")
	await _settle()
	_moor_at(&"copenhagen", 13.0)
	var companion := GameSession.get_companions()[0]
	GameSession.set_companion_area(CompanionState.AREA_SHORE, 0, companion.id)
	front = await _quay()
	t.check(front.get_companion_nodes().size() == 1, "[café] a companion ashore follows the Captain onto the quay")
	front.player.position = front.get_station(QuayLayout.CAFE).position + Vector2(0, 6)
	await t.physics_frames(2)
	GameSession.buy_cafe_coffee()
	front.sit_at_cafe()
	var node := front.get_companion_nodes()[0]
	await t.wait_until(func() -> bool: return node.is_resting(), 6.0)
	t.check(node.is_resting() and node.position.distance_to(front.seat.at) < 70.0, "[café] it settles beside the Captain's chair")
	front.stand_up()
	app.recall_companion()
	front.refresh()
	await t.frames(2)
	t.check(front.get_companion_nodes().is_empty(), "[café] called aboard from the quay, it leaves the quay")


func _test_people() -> void:
	var front := app.router.current_screen as HarbourFront
	var life := front.life
	var noon := GameSession.get_game_time()
	t.check(life.roster_at(noon) == life.roster_at(noon), "[people] who is about is the same for the same harbour and hour")
	var midnight := noon + 11.0 * 3600.0  # 00:00 local
	var at_night := life.roster_at(midnight)
	t.check(at_night.size() <= 2, "[people] few or none at night (%d)" % at_night.size())
	life.weather_factor_override = 0.0
	var storm := life.roster_at(noon).filter(func(e: Dictionary) -> bool: return e.role != HarbourLife.ROLE_KEEPER)
	life.weather_factor_override = -1.0
	t.check(storm.is_empty(), "[people] nobody strolls in a gale")
	var big := 0
	var little := 0
	var small_life := HarbourLife.new()
	small_life.layout = QuayLayout.build(&"lohals")
	small_life.port_id = &"lohals"
	for h in range(8, 20):
		big += life.roster_at(noon + (h - 13) * 3600.0).size()
		little += small_life.roster_at(noon + (h - 13) * 3600.0).size()
	small_life.free()
	t.check(big > little, "[people] busier in a major harbour than a small one (%d vs %d over the day)" % [big, little])
	t.check(life.get_people().all(func(p: Node) -> bool: return not p is PhysicsBody2D and not p is CollisionObject2D),
		"[people] the townsfolk have no physics body: they never push the Captain")
	# Watch them for a while: nobody lingers in a doorway or at the walkway.
	var in_the_way := 0
	for step in 120:
		life._process(0.25)
		for person in life.get_people():
			if person.visible and person.state == &"pause" and front.layout.is_in_the_way(person.position):
				in_the_way += 1
	t.check(in_the_way == 0, "[people] watched for half a minute, nobody stops in a doorway or at the walkway (%d)" % in_the_way)
	# A shopkeeper locks up just after closing time.
	var close := BusinessHours.hours(QuayLayout.CHANDLERY, &"copenhagen").y
	var keepers := life.roster_at(noon + (close - 13.0 + 0.1) * 3600.0).filter(func(e: Dictionary) -> bool:
		return e.role == HarbourLife.ROLE_KEEPER and e.business == QuayLayout.CHANDLERY)
	t.check(keepers.size() == 1, "[people] at the chandlery's closing time its shopkeeper locks up")
	# After a time skip the quay is rebuilt for the new hour, no backlog.
	var count_before := life.get_person_count()
	var state := GameSession.get_state_snapshot()
	state.game_time += 11.0 * 3600.0
	GameSession.replace_state(state)
	life._check = 0.0
	life._process(0.01)
	t.check(life.get_person_count() <= 2 and count_before >= 1, "[people] after a jump to midnight the quay shows the night's few at once (%d, was %d)" % [
		life.get_person_count(), count_before])


func _test_wheel_and_keys() -> void:
	_moor_at(&"copenhagen", 11.0)
	var front := app.router.current_screen as HarbourFront
	if front == null or front.port_id != &"copenhagen":
		front = await _quay()
	app.modals.clear()
	var ids: Array = app.get_wheel_actions().map(func(a: Dictionary) -> StringName: return a.id)
	t.check(&"back_aboard" in ids and &"log" in ids and not &"set_sail" in ids and not &"fishing" in ids and not &"chart" in ids,
		"[wheel] on the quay the wheel offers going back aboard and the log; no setting sail, rod or charts (%s)" % [ids])
	await t.press_action(&"reel_in")
	await t.frames(2)
	t.check(app.modals.is_empty(), "[keys] R does nothing on the quay (the rod is aboard)")
	await t.press_action(&"pause")
	await t.frames(2)
	t.check(app.modals.get_top() is PauseMenu and t.get_tree().paused, "[keys] Esc opens the pause menu, as aboard")
	app.modals.clear()
	await t.frames(2)
	t.check(app.quicksave_blocker() == "", "[keys] F5 quicksaves on the quay too")


func _test_save_on_the_quay() -> void:
	var front := app.router.current_screen as HarbourFront
	front.player.position = front.layout.door_station(QuayLayout.GROCERY) + Vector2(0, 30)
	var snapshot := GameSession.get_state_snapshot()
	t.check(snapshot.boat_area == SessionState.AREA_EXTERIOR, "[save] a save on the quay has the Captain on deck")
	var err := SaveManager.save_to_slot(1, snapshot)
	var result := SaveManager.load_from_slot(1)
	t.check(err == OK and result.is_ok() and SaveManager.SAVE_VERSION == 12, "[save] it saves and loads in format 12 (no new field)")
	app.load_slot(1)
	await _settle()
	var deck := app.router.current_screen as BoatArea
	t.check(deck != null and deck.area_id == SessionState.AREA_EXTERIOR, "[save] loading it returns to the boat")
	if deck:
		t.check(deck.player.position.distance_to(deck.get_walkway_return_point()) < 40.0,
			"[save] on the pontoon, by the walkway (%s)" % deck.player.position)
	SaveManager.delete_slot(1)  # the slots stay empty for the suites after this one


func _test_walk_back_down() -> void:
	var front := await _quay()
	front.player.position = front.layout.arrival_point()
	await t.physics_frames(2)
	await t.hold_actions([&"move_down"], 1.2)
	await _settle()
	var deck := app.router.current_screen as BoatArea
	t.check(deck != null and deck.player.position.distance_to(deck.get_walkway_return_point()) < 40.0,
		"[leave] walking back down the walkway returns to the deck, by the walkway")


## The quay's own views fit at every promised size, scale and language.
func _test_layout() -> void:
	_moor_at(&"copenhagen", 11.0)
	var front := await _quay()
	if front == null:
		return
	var problems: Array[String] = await ViewFit.problems(t, app, {
		"café": func() -> void: app.open_cafe(),
		"harbour office": func() -> void: app.open_harbour_office(false),
		"hatch": func() -> void: app.open_harbour_office(true),
		"noticeboard": func() -> void: app.open_noticeboard(),
		"chandlery": func() -> void: app.open_chandlery(),
	})
	t.check(problems.is_empty(), "[layout] the café, the office, its hatch, the noticeboard and a shop counter fit at 1280x720 and 1024x768, 100 %% and 130 %%, English and Danish %s" % [problems])
