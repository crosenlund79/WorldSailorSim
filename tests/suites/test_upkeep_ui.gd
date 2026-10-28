extends RefCounted
## Iteration 005b through the real application: the provisions station and
## panel in every cabin, the supply graphics, the HUD status line, damage
## overlays on all three boats, the boatyard (fixed size, repair, restock),
## the rescue report, the development test panel (and that players never see
## it), and the ship's companion no longer blocking stations.

const APP_SCENE := preload("res://src/app/app.tscn")
const W := preload("res://tests/helpers/walkability.gd")
const VESSELS: Array[StringName] = [&"starling_33", &"halcyon_40", &"petrel_36"]

var t: Node
var app: Node


func run(runner: Node) -> void:
	t = runner
	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	Simulation.auto_advance = false
	t.use_calm_wind()
	WeatherFixtures.clear()
	app.start_new_game()
	await _settle()

	await _test_hud_status()
	await _test_provisions_station()
	await _test_supply_graphics()
	await _test_all_cabins()
	await _test_damage_visuals()
	await _test_boatyard()
	await _test_rescue_flow()
	await _test_dev_panel()
	await _test_production_isolation()
	await _test_companion_overlap()

	DevTools.force_enabled = null
	DevTools.restore_normal_weather()
	SettingsManager.set_ui_scale(1.0)
	Simulation.auto_advance = true
	app.queue_free()
	await t.frames(2)
	GameSession.end_session()
	t.use_calm_wind()


# --- Helpers ------------------------------------------------------------------------

func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)


func _area() -> BoatArea:
	return app.router.current_screen as BoatArea


## Shows `area` of the current boat with the player at `spawn`.
func _show(area: StringName, spawn: StringName) -> void:
	app.modals.clear()
	GameSession.enter_boat_area(area, spawn)
	app._show_current_boat_area()
	await _settle()


func _station(area: BoatArea, interaction_id: StringName) -> Interactable:
	for node: Interactable in area.get_node("Layout/Stations").get_children():
		if node.interaction_id == interaction_id:
			return node
	return null


## Puts the player where `interaction_id` is focused and presses E.
func _use_station(interaction_id: StringName) -> bool:
	var area := _area()
	var station := _station(area, interaction_id)
	if station == null:
		return false
	var cells := W.walkable_cells(area, area.get_spawn_position(&"start"))
	var tries := 0
	for p in W.use_points(station, cells):
		area.player.position = p
		await t.physics_frames(3)
		if area.player.get_focused_interactable() == station:
			await t.press_action(&"interact")
			await t.frames(2)
			return true
		tries += 1
		if tries > 40:
			break
	return false


func _set_companion(kind: StringName, spot: StringName) -> void:
	var state := GameSession.get_state_snapshot()
	state.companion = CompanionState.create(kind, state.game_time)
	state.companion.spot = spot
	GameSession.replace_state(state)


func _toast_contains(text: String) -> bool:
	for message in app.toasts.get_messages():
		if text in message:
			return true
	return false


# --- HUD -----------------------------------------------------------------------------

func _test_hud_status() -> void:
	app.hud.refresh()
	var status := (app.hud.find_child("StatusLabel", true, false) as Label)
	t.check(status.is_visible_in_tree() and status.text.contains("Hull 100 % · Sound") and status.text.contains("€10,000")
		and status.text.contains("Food 14.0 d") and status.text.contains("Water 14.0 d"),
		"[hud] the HUD shows hull condition, money, food and water (%s)" % status.text)
	var route := app.hud.find_child("RoutePanel", true, false) as Control
	var area_panel := app.hud.find_child("AreaPanel", true, false) as Control
	t.check(not area_panel.get_global_rect().intersects(route.get_global_rect()) \
		and not area_panel.get_global_rect().intersects((app.hud.get_node("ClockPanel") as Control).get_global_rect()),
		"[hud] the status line does not cover the clock or route panels")


# --- Provisions ---------------------------------------------------------------------

func _test_provisions_station() -> void:
	await _show(SessionState.AREA_INTERIOR, &"start")
	t.check(await _use_station(&"provisions"), "[provisions] the cabin's provisions station can be used")
	var menu := app.modals.get_top() as ProvisionsMenu
	if not t.check(menu != null, "[provisions] it opens the provisions panel"):
		return
	var before := menu.get_values()
	t.check(before.food == "14.0 days" and before.water == "14.0 days" and before.endurance == "14.0 days" and before.food_level == "Full",
		"[provisions] it shows food, water and endurance in days (%s)" % [before])
	# Iteration 16: with the everyday stores full the grocery still offers the
	# long-passage stock-up (up to the boat's passage stores).
	t.check(not (menu.find_child("GroceryButton", true, false) as Button).disabled and GameSession.get_provisions_price() == 0,
		"[provisions] everyday stores full: nothing more to buy for them; the grocery still offers a long-passage stock-up")
	t.check(t.get_tree().paused, "[provisions] the game is paused while it is open")
	await t.screenshot("89_provisions_before_sleep")
	menu.close()
	await t.frames(2)
	# Sleep a known time and look again.
	app.sleep_for(12.0)
	await _settle()
	t.check(await _use_station(&"provisions"), "[provisions] after sleeping, check again")
	menu = app.modals.get_top() as ProvisionsMenu
	var after := menu.get_values() if menu else {}
	t.check(after.get("food") == "13.5 days" and after.get("water") == "13.5 days",
		"[provisions] 12 hours of sleep used half a day (%s)" % [after])
	await t.screenshot("90_provisions_after_sleep")
	# Buy in harbour: the panel leads to the grocery store (Iteration 005c).
	var grocery_button := menu.find_child("GroceryButton", true, false) as Button
	t.check(not grocery_button.disabled and grocery_button.text.contains("€10"), "[buy] used stores: the grocery store is offered (%s)" % grocery_button.text)
	await t.click(grocery_button)
	await t.frames(2)
	var store := app.modals.get_top() as GroceryMenu
	if t.check(store != null, "[buy] it opens the grocery store on top"):
		await t.click(store.get_buy_button())
		await t.frames(2)
		store.close()
		await t.frames(2)
	t.check(app.modals.get_top() == menu and menu.get_values().food == "14.0 days" and is_equal_approx(GameSession.get_food_days(), 14.0),
		"[buy] back in the provisions panel: full again (14 days)")
	t.check_eq(GameSession.get_funds(), 9990, "[buy] one missing day of food and water in all cost €10")
	menu.close()
	await t.frames(2)


func _test_supply_graphics() -> void:
	var display := _area().find_child("ProvisionDisplay", true, false) as ProvisionDisplay
	if not t.check(display != null and display.is_visible_in_tree(), "[supplies] the food and water stores are drawn in the cabin"):
		return
	var seen := {}
	for days in [14.0, 7.0, 3.0, 0.0]:
		DevTools.set_provisions(days)
		await t.frames(2)
		seen[days] = [display.get_level(), display.get_filled()]
		if days == 14.0:
			await t.screenshot("91_supplies_full")
		elif days == 3.0:
			await t.screenshot("92_supplies_low")
	t.check(seen[14.0] == [Provisions.LEVEL_FULL, Vector2i(4, 4)] and seen[7.0] == [Provisions.LEVEL_MODERATE, Vector2i(2, 2)]
		and seen[3.0] == [Provisions.LEVEL_LOW, Vector2i(1, 1)] and seen[0.0] == [Provisions.LEVEL_EMPTY, Vector2i(0, 0)],
		"[supplies] full, moderate, low and empty look different (%s)" % [seen])
	# They follow the real consumption.
	DevTools.set_provisions(7.1)
	await t.frames(2)
	var filled_before := display.get_filled()
	Simulation.advance(0.2 * Provisions.DAY_SECONDS)
	await t.frames(2)
	t.check(filled_before == Vector2i(3, 3) and display.get_filled() == Vector2i(2, 2), "[supplies] a crate and a can empty as time passes")
	GameSession.buy_provisions()
	await t.frames(2)
	t.check_eq(display.get_filled(), Vector2i(4, 4), "[supplies] buying fills the store graphics at once")


func _test_all_cabins() -> void:
	for id in VESSELS:
		GameSession.switch_vessel(id)
		await _show(SessionState.AREA_INTERIOR, &"start")
		var area := _area()
		var station := _station(area, &"provisions")
		var display := area.find_child("ProvisionDisplay", true, false) as ProvisionDisplay
		var cells := W.walkable_cells(area, area.get_spawn_position(&"start"))
		t.check(station != null and not W.use_points(station, cells).is_empty(),
			"[cabins] the %s has a reachable provisions station" % id)
		t.check(display != null and station != null and display.position.distance_to(station.position) < 80.0,
			"[cabins] the %s shows its food and water stores beside it" % id)
		t.check(await _use_station(&"provisions") and app.modals.get_top() is ProvisionsMenu, "[cabins] on the %s it opens the panel" % id)
		app.modals.clear()
		await t.frames(2)
		if id == &"halcyon_40":
			await t.screenshot("99_halcyon_cabin")
			var door := _station(area, &"companionway")
			var label := area.find_child("Door", true, false) as Label
			t.check(label != null and label.visible and label.text == "TO DECK" and label.get_global_rect().get_center().distance_to(door.global_position) < 90.0,
				"[cabins] the Halcyon's exit is marked TO DECK right at the door")
			area.player.position = area.get_spawn_position(&"from_deck")
			await t.physics_frames(3)
			t.check_eq(app.hud.get_prompt(), "Go on deck", "[cabins] standing at the Halcyon's door shows 'Go on deck'")
			await t.screenshot("100_halcyon_cabin_exit")
	GameSession.switch_vessel(&"starling_33")


# --- Damage -----------------------------------------------------------------------------

func _test_damage_visuals() -> void:
	var number := 80
	for id in VESSELS:
		GameSession.switch_vessel(id)
		await _show(SessionState.AREA_EXTERIOR, &"from_boatyard")
		var visual := _area().get_node("Visual") as VesselVisual
		var counts := {}
		for percent in DevTools.CONDITION_PRESETS:
			DevTools.set_condition(percent)
			await t.frames(2)
			var overlay := visual.get_damage_overlay()
			counts[percent] = overlay.get_visible_mark_count() if overlay else -1
			if percent in [100.0, 40.0, 15.0]:
				await t.screenshot("%d_damage_%s_%d" % [number, id, percent])
				number += 1
		t.check(counts[100.0] == 0 and counts[75.0] > 0 and counts[40.0] > counts[75.0] and counts[15.0] > counts[40.0]
			and counts[1.0] == counts[15.0], "[damage] the %s shows more damage as its condition drops (%s)" % [id, counts])
		var overlay := visual.get_damage_overlay()
		t.check(overlay != null and overlay.band == VesselCondition.BAND_CRITICAL and _area().get_node("Layout").get_index() > visual.get_index(),
			"[damage] the overlay is part of the art, under the stations and markers")
		app.hud.refresh()
		t.check((app.hud.find_child("StatusLabel", true, false) as Label).text.contains("Hull 1 % · Critical"), "[damage] the HUD says 'Critical'")
		# The cabin shows it too, and a repair clears it.
		await _show(SessionState.AREA_INTERIOR, &"start")
		var cabin_overlay := (_area().get_node("Visual") as VesselVisual).get_damage_overlay()
		t.check(cabin_overlay != null and cabin_overlay.get_visible_mark_count() > 0, "[damage] the %s's cabin shows the damage" % id)
		GameSession.repair_vessel()
		await t.frames(2)
		t.check(cabin_overlay.get_visible_mark_count() == 0, "[damage] repaired: the damage graphics are gone")
	GameSession.switch_vessel(&"starling_33")


# --- Boatyard -----------------------------------------------------------------------------

func _open_boatyard() -> BoatyardMenu:
	await _show(SessionState.AREA_EXTERIOR, &"from_boatyard")
	app.open_boatyard()
	await t.frames(3)
	return app.modals.get_top() as BoatyardMenu


func _test_boatyard() -> void:
	DevTools.set_condition(40.0)
	DevTools.set_provisions(5.0)
	var yard := await _open_boatyard()
	if not t.check(yard != null, "[boatyard] opens in harbour"):
		return
	for scale in [1.0, 1.3]:
		SettingsManager.set_ui_scale(scale)
		await t.frames(3)
		var rects := {}
		for id in VESSELS:
			yard.select(id)
			await t.frames(3)
			rects[id] = yard.get_panel_rect()
			if scale == 1.0:
				await t.screenshot("10%d_boatyard_%s" % [VESSELS.find(id) + 2, id])
		var first: Rect2 = rects[VESSELS[0]]
		var same := rects.values().all(func(r: Rect2) -> bool: return r.position.distance_to(first.position) < 0.5 and r.size.distance_to(first.size) < 0.5)
		t.check(same, "[boatyard] at %d%% the panel keeps its size and place for all three boats (%s)" % [roundi(scale * 100), first])
		var screen := Rect2(Vector2.ZERO, yard.get_viewport_rect().size)
		var buttons_ok := true
		for name in ["ChooseButton", "CloseButton", "CareButton"]:
			var b := yard.find_child(name, true, false) as Control
			buttons_ok = buttons_ok and b.is_visible_in_tree() and screen.encloses(b.get_global_rect()) and first.encloses(b.get_global_rect())
		t.check(buttons_ok, "[boatyard] at %d%% all buttons are inside the panel and on screen" % roundi(scale * 100))
	SettingsManager.set_ui_scale(1.0)
	await t.frames(3)
	yard.select(&"starling_33")
	await t.frames(2)
	var condition := yard.find_child("ConditionLabel", true, false) as Label
	t.check(condition.text.contains("40 % · Damaged"), "[boatyard] it shows the selected boat's condition (%s)" % condition.text)
	var care := yard.find_child("CareButton", true, false) as Button
	# I026: the grocery store has its own shop on the quay; the yard is no
	# longer the way there.
	t.check(not care.disabled and care.text.contains("needs attention") and yard.find_child("GroceryButton", true, false) == null,
		"[boatyard] Boat care (%s) is offered for a worn boat; the grocery is its own shop now" % care.text)
	await t.screenshot("94_boatyard_repair")
	var funds := GameSession.get_funds()
	var price := GameSession.get_provisions_price()
	var repair_cost := int(GameSession.service_quote(BoatCare.SERVICE_REPAIR).cost)
	app.open_grocery()  # (the store itself; reached from its door on the quay or the cabin's locker)
	await t.frames(2)
	var store := app.modals.get_top() as GroceryMenu
	if store:
		await t.click(store.get_buy_button())
		store.close()
		await t.frames(2)
	await t.click(care)
	await t.frames(2)
	var menu := app.modals.get_top() as BoatCareMenu
	if t.check(menu != null, "[boatyard] Boat care opens on top of the boatyard"):
		await t.click(menu.get_service_button(BoatCare.SERVICE_REPAIR))
		menu.close()
		await t.frames(2)
	# The repair's few hours ashore use a little food.
	t.check(is_equal_approx(GameSession.get_condition(), 100.0) and GameSession.get_food_days() > 13.7
		and GameSession.get_funds() == funds - price - repair_cost and price == 180,
		"[boatyard] repaired for %s; provisions bought for €180 (9 + 9 days)" % GameSession.format_money(repair_cost))
	t.check(app.modals.get_top() == yard and not care.text.contains("needs attention") and condition.text.contains("100 %"),
		"[boatyard] back in the boatyard, the buttons and condition update at once")
	await t.screenshot("93_boatyard_after_repair_restock")
	yard.close()
	await t.frames(2)
	t.check(app.modals.is_empty(), "[boatyard] Close closes it")


# --- Rescue ------------------------------------------------------------------------------

func _test_rescue_flow() -> void:
	await _show(SessionState.AREA_INTERIOR, &"start")
	GameSession.plan_route_to(&"kiel")
	GameSession.depart()
	Simulation.advance(3600.0)
	t.check(DevTools.prepare_rescue() == "", "[rescue] the developer rescue test is ready at sea")
	# The storm is on the chart and makes the real weather at the boat.
	var here := Simulation.get_weather_at_vessel()
	t.check(here.event_id == &"dev_storm" and here.hazard >= WeatherModel.HAZARD_DANGEROUS,
		"[rescue] the test storm is the real weather at the boat (%s)" % here.get_label())
	var funds_before := GameSession.get_funds()
	Simulation.advance(600.0)
	await t.frames(3)
	await _settle()
	var dialog := app.modals.get_top() as RescueDialog
	if not t.check(dialog != null, "[rescue] the rescue report appears"):
		return
	var text := dialog.get_text()
	t.check(text.contains("Rescued at Sea") and text.contains("Copenhagen") and text.contains("€1,000")
		and text.contains(GameSession.format_money(funds_before - 1000)) and GameSession.get_funds() == funds_before - 1000,
		"[rescue] it names Copenhagen, the €1,000 fee and the %s left" % GameSession.format_money(funds_before - 1000))
	t.check(t.get_tree().paused, "[rescue] the game is paused under the report")
	var time := GameSession.get_game_time()
	await t.frames(10)
	t.check_eq(GameSession.get_game_time(), time, "[rescue] no time passes while it is open")
	await t.screenshot("97_rescue_dialog")
	await t.click(dialog.find_child("ContinueButton", true, false) as Button)
	await _settle()
	t.check(not t.get_tree().paused and app.modals.is_empty(), "[rescue] Continue: the game goes on")
	var area := _area()
	t.check(area != null and area.area_id == SessionState.AREA_INTERIOR, "[rescue] aboard, in the cabin")
	app.hud.refresh()
	t.check((app.hud.find_child("LocationLabel", true, false) as Label).text.contains("Copenhagen"), "[rescue] the HUD says Copenhagen")
	t.check_eq(GameSession.get_time_scale(), 1, "[rescue] at 1× time")
	DevTools.restore_normal_weather()
	await _show(SessionState.AREA_EXTERIOR, &"from_cabin")
	await t.screenshot("98_copenhagen_after_rescue")
	# A rescue during sleep: the report, no "You slept" message, no voyage left.
	GameSession.plan_route_to(&"kiel")
	GameSession.depart()
	Simulation.advance(1800.0)
	DevTools.prepare_rescue()
	var funds_second := GameSession.get_funds()
	app.sleep_for(8.0)
	await _settle()
	t.check(app.modals.get_top() is RescueDialog and not GameSession.is_underway() and GameSession.get_funds() == funds_second - 1000,
		"[rescue] during sleep: woken by the rescue, another €1,000 paid")
	t.check(not _toast_contains("You slept"), "[rescue] no ordinary wake-up message")
	app.modals.get_top().close()
	await _settle()
	DevTools.restore_normal_weather()


# --- Developer tools ---------------------------------------------------------------------

func _test_dev_panel() -> void:
	DevTools.force_enabled = true
	await _show(SessionState.AREA_INTERIOR, &"start")
	await t.press_key(KEY_F10)
	var panel := app.modals.get_top() as DevTestPanel
	if not t.check(panel != null, "[dev] F10 opens the developer test panel"):
		return
	var names := ["NormalWeather", "Gale", "Storm", "Squall", "StormAhead", "Condition100", "Condition75", "Condition40",
		"Condition15", "Condition1", "RescueTest", "Stores3", "Stores0", "Advance1", "Advance6"]
	t.check(names.all(func(n: String) -> bool: return panel.get_button(n) != null), "[dev] weather, condition, rescue, stores and time tests are there")
	t.check((panel.find_child("Status", true, false) as Label).text.contains("Test weather: none"), "[dev] it shows that no test weather is active")
	# A severe storm 20 nm ahead (needs a voyage): refused in harbour, works at sea.
	await t.click(panel.get_button("StormAhead"))
	t.check(not DevTools.is_scenario_active() and _toast_contains("Set sail first"), "[dev] a storm on the course needs a course")
	panel.close()
	await t.frames(2)
	GameSession.plan_route_to(&"kiel")
	GameSession.depart()
	Simulation.advance(1800.0)
	await t.press_key(KEY_F10)
	panel = app.modals.get_top() as DevTestPanel
	await t.click(panel.get_button("StormAhead"))
	t.check(DevTools.scenario == DevTools.SCENARIO_STORM_AHEAD and (panel.find_child("Status", true, false) as Label).text.contains("active"),
		"[dev] the storm ahead is active and the panel says so")
	var hazards := Simulation.get_hazards_ahead(Simulation.WARNING_HORIZON_HOURS)
	t.check(hazards.any(func(h: Dictionary) -> bool: return h.event_id == &"dev_storm_ahead" and h.hazard >= WeatherModel.HAZARD_DANGEROUS),
		"[dev] the real route forecast sees it ahead")
	panel.close()
	await t.frames(2)
	app.open_chart()
	await _settle()
	var map := app.router.current_screen as WorldMap
	if map:
		var view := map.get_map_view()
		view.center_on_geo(GameSession.get_vessel_position() + Vector2(0.0, -0.2), 2.0)
		await t.frames(4)
		t.check(view.get_weather_shapes().any(func(s: Dictionary) -> bool: return s.event.id == &"dev_storm_ahead"),
			"[dev] the chart shows the test storm")
		map.show_tab(WorldMap.TAB_WEATHER)
		map._refresh()
		await t.frames(3)
		await t.screenshot("95_test_storm_chart")
		# Squall at the boat: chart and warning.
		await t.press_key(KEY_F10)
		panel = app.modals.get_top() as DevTestPanel
		await t.click(panel.get_button("Squall"))
		panel.close()
		await t.frames(2)
		var warned := []
		var on_warning := func(w: Dictionary) -> void: warned.append(w)
		Simulation.weather_warning.connect(on_warning)
		Simulation.advance(600.0)
		Simulation.weather_warning.disconnect(on_warning)
		await t.frames(4)
		t.check(warned.any(func(w: Dictionary) -> bool: return w.event_id == &"dev_squall"), "[dev] the squall gives a real weather warning")
		t.check(Simulation.get_weather_at_vessel().classification in [WeatherModel.CLASS_SQUALL, WeatherModel.CLASS_THUNDERSTORM],
			"[dev] the weather at the boat is a thunderstorm / squall")
		view.center_on_geo(GameSession.get_vessel_position(), 3.0)
		await t.frames(4)
		await t.screenshot("96_test_squall_chart")
		# The chart sidebar keeps its size with long hazard lists on every tab.
		var rects := []
		for tab in [WorldMap.TAB_WEATHER, WorldMap.TAB_COURSE, WorldMap.TAB_DETAILS, WorldMap.TAB_WEATHER]:
			map.show_tab(tab)
			map._refresh()
			await t.frames(3)
			var side := map.find_child("SidePanel", true, false) as Control
			var footer := map.find_child("Footer", true, false) as Control
			rects.append([side.get_global_rect(), footer.get_global_rect()])
		var stable := rects.all(func(r: Array) -> bool: return r[0].is_equal_approx(rects[0][0]) and r[1].is_equal_approx(rects[0][1]))
		t.check(stable, "[chart] with test weather listed, the sidebar and its footer keep their size on every tab")
		app.close_chart()
		await _settle()
	# Normal weather removes it; test weather is never saved.
	DevTools.activate_scenario(DevTools.SCENARIO_STORM)
	var saved := GameSession.get_state_snapshot()
	var weather_section: Dictionary = saved.to_dict().weather
	t.check(weather_section.keys() == ["model_version", "exposure"] and not JSON.stringify(saved.to_dict()).contains("peak_kn"),
		"[dev] test weather is not part of a saved game (no event data in the save)")
	DevTools.restore_normal_weather()
	t.check(WeatherModel.get_default().fixture_events.is_empty() and WeatherModel.get_default().generated_enabled and not DevTools.is_scenario_active(),
		"[dev] Normal weather restores the ordinary weather model")
	DevTools.activate_scenario(DevTools.SCENARIO_GALE)
	GameSession.replace_state(saved)
	t.check(not DevTools.is_scenario_active() and WeatherModel.get_default().fixture_events.is_empty(),
		"[dev] loading a game removes any test weather")
	# Repeatable: the same state gives the same storm.
	DevTools.activate_scenario(DevTools.SCENARIO_STORM)
	var first := Simulation.get_weather_at_vessel().to_dict()
	DevTools.activate_scenario(DevTools.SCENARIO_STORM)
	t.check_eq(Simulation.get_weather_at_vessel().to_dict(), first, "[dev] activating a scenario twice gives the same weather")
	DevTools.restore_normal_weather()
	t.use_calm_wind()


func _test_production_isolation() -> void:
	DevTools.force_enabled = false
	await _show(SessionState.AREA_INTERIOR, &"start")
	await t.press_key(KEY_F10)
	t.check(not (app.modals.get_top() is DevTestPanel), "[dev] in a player's build F10 does nothing")
	app.open_pause_menu()
	await t.frames(2)
	var pause: ModalPanel = app.modals.get_top()
	t.check(pause is PauseMenu and pause.find_child("DevTestsButton", true, false) == null, "[dev] and the pause menu has no developer tests")
	app.modals.clear()
	await t.frames(2)
	t.check(DevTools.activate_scenario(DevTools.SCENARIO_STORM) != "" and not DevTools.is_scenario_active(),
		"[dev] test weather cannot be made in a player's build")
	DevTools.force_enabled = true
	app.open_pause_menu()
	await t.frames(2)
	t.check(app.modals.get_top().find_child("DevTestsButton", true, false) != null, "[dev] in a development build the pause menu offers it")
	app.modals.clear()
	await t.frames(2)


# --- Companion overlap -----------------------------------------------------------------------

## Interactables the sensor of a player at `p` would have in range, with the
## companion's petting area moved to `cat_at`.
func _in_reach(area: BoatArea, pet: Interactable, p: Vector2) -> Array[Interactable]:
	var found: Array[Interactable] = []
	for station: Interactable in area.get_node("Layout/Stations").get_children():
		if station.enabled and W.distance_to_station(station, p) <= 46.0:
			found.append(station)
	if p.distance_to(pet.global_position) <= ShipCompanion.INTERACT_RADIUS + 46.0:
		found.append(pet)
	return found


func _test_companion_overlap() -> void:
	DevTools.force_enabled = null
	app.start_new_game()  # moored in harbour, so every boat can be boarded
	await _settle()
	for id in VESSELS:
		GameSession.switch_vessel(id)
		await _show(SessionState.AREA_INTERIOR, &"start")
		var area := _area()
		var companion := area.find_child("Companion", true, false) as ShipCompanion
		var pet := companion.interactable
		var cells := W.walkable_cells(area, area.get_spawn_position(&"start"))
		var blocked := []
		var unpettable := []
		for spot in CompanionState.get_spot_ids(CompanionState.KIND_CAT):
			companion.position = companion.get_spot_position(spot)
			for station: Interactable in area.get_node("Layout/Stations").get_children():
				if not station.enabled:
					continue
				var usable := false
				for p in W.use_points(station, cells):
					var toward := (station.global_position - p).normalized()
					if InteractionSensor.choose(_in_reach(area, pet, p), p, toward) == station:
						usable = true
						break
				if not usable:
					blocked.append("%s:%s" % [spot, station.interaction_id])
			var pettable := false
			for p in cells:
				if p.distance_to(companion.position) <= ShipCompanion.INTERACT_RADIUS + 40.0 \
						and InteractionSensor.choose(_in_reach(area, pet, p), p, (companion.position - p).normalized()) == pet:
					pettable = true
					break
			if not pettable:
				unpettable.append(spot)
		t.check(blocked.is_empty(), "[companion] on the %s the cat never blocks a station or door, wherever it rests %s" % [id, blocked if blocked else ""])
		t.check(unpettable.is_empty(), "[companion] on the %s the cat can be petted at every resting spot %s" % [id, unpettable if unpettable else ""])

	# In play, on the Starling: the cat rests by the galley, right at the provisions.
	GameSession.switch_vessel(&"starling_33")
	_set_companion(CompanionState.KIND_CAT, &"companionway")
	await _show(SessionState.AREA_INTERIOR, &"start")
	var area := _area()
	var companion := area.find_child("Companion", true, false) as ShipCompanion
	var provisions := _station(area, &"provisions")
	t.check(companion.position.distance_to(provisions.position) < 60.0, "(setup) the cat rests right next to the provisions station")
	area.player.position = provisions.position + Vector2(-4, 18)
	area.player.set_facing(Vector2.UP)  # facing the galley counter
	await t.physics_frames(3)
	t.check(area.player.get_focused_interactable() == provisions and app.hud.get_prompt() == "Check provisions",
		"[companion] at the station the prompt says 'Check provisions' (%s)" % app.hud.get_prompt())
	await t.screenshot("101_cat_near_provisions")
	await t.press_action(&"interact")
	await t.frames(2)
	t.check(app.modals.get_top() is ProvisionsMenu, "[companion] and E opens the provisions, not the cat")
	app.modals.clear()
	await t.frames(2)
	# A step towards the cat, facing it: now it is the cat.
	area.player.position = companion.position + Vector2(40, 10)
	area.player.set_facing((companion.position - area.player.position).normalized())
	await t.physics_frames(3)
	t.check(area.player.get_focused_interactable() == companion.interactable and app.hud.get_prompt() == "Pet the cat",
		"[companion] a step over, facing the cat, the prompt says 'Pet the cat' (%s)" % app.hud.get_prompt())
	await t.press_action(&"interact")
	await t.frames(2)
	t.check(companion.is_reacting(), "[companion] and E pets the cat")
