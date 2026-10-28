extends RefCounted
## I026 stage 03, marine electronics.
## 1. The instruments read the authoritative data (GameSession, Simulation,
##    WorldMap.get_next_turn) and nothing else: every value equals its
##    source; depth only at anchor (the anchor's own, a game estimate).
## 2. One cluster on the HUD, underway, on deck and in the cabin; the old
##    floating panels are gone; a few readings a second, not every frame.
## 3. The three packages: bought at the chandlery (its own purchase flow),
##    fitted to the boat aboard, owned for good and selectable on any boat;
##    the choice and the pages persist through save and load; older saves
##    get Classic; the save format stays 12.
## 4. Every boat has its cockpit electronics at the helm, the plotter has
##    its station, and the units open their focused views (E, a click).
## 5. The focused views: I and P open them, Esc closes them; the pages and
##    layouts change and stay in their slots (the essentials stay shown).
## 6. Layout: the cluster and the views fit at 1280 x 720 and 1024 x 768, at
##    interface size 100 % and 130 %, in English and Danish, beside the
##    other HUD pieces.

const APP_SCENE := preload("res://src/app/app.tscn")
const Face := preload("res://src/electronics/instrument_face.gd")
const DECK := SessionState.AREA_EXTERIOR
const CABIN := SessionState.AREA_INTERIOR

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
	t.set_wind(250.0, 13.0)
	await _test_packages_and_saves()
	await _test_cockpit_on_every_boat()
	GameSession.plan_route_to(&"kiel")
	GameSession.depart()
	Simulation.advance(3600.0)
	await _show(DECK)
	await _test_authoritative_values()
	await _test_cluster()
	await _test_focused_views()
	await _test_layout()
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
	app.toasts.clear()
	app.hud.hide_warning()
	return app.router.current_screen as BoatArea


# --- 3. Packages, the chandlery and saves ---------------------------------------------------------

func _test_packages_and_saves() -> void:
	t.check_eq(SaveManager.SAVE_VERSION, 12, "[save] the save format stays 12")
	t.check_eq(InstrumentPackage.get_ids(), [InstrumentPackage.CLASSIC, InstrumentPackage.MODERN, InstrumentPackage.OFFSHORE] as Array[String],
		"[packages] three packages, Classic first")
	var classic := InstrumentPackage.get_package(InstrumentPackage.CLASSIC)
	t.check(classic.price == 0 and GameSession.get_instrument_package().id == InstrumentPackage.CLASSIC and GameSession.get_instruments().is_default(),
		"[packages] a new game: Classic fitted, free, nothing bought")
	for package in InstrumentPackage.get_all():
		var essentials: Array[String] = []
		for i in package.default_pages.size():
			essentials.append_array(package.slot_pages(i))
		t.check(package.get_display_name() != "" and package.get_text() != "" and package.model.begins_with(InstrumentPackage.brand()),
			"[packages] %s has a name, a description and a model of the (fictional) maker" % package.id)
		if package.units == InstrumentPackage.UNITS_DISPLAYS:
			for i in package.default_pages.size():
				t.check(package.default_pages[i] in package.slot_pages(i), "[packages] %s display %d starts on a page of its slot" % [package.id, i])
	# The chandlery: its rows, the purchase flow, the prices.
	await _show(DECK)
	var funds := GameSession.get_funds()
	var menu: ChandleryMenu = app.open_chandlery()
	await t.frames(3)
	if not t.check(menu != null and menu.find_child("ElectronicsHeading", true, false) != null, "[chandlery] an Electronics section"):
		return
	var modern := menu.get_row_button("instruments_%s" % InstrumentPackage.MODERN)
	var offshore := menu.get_row_button("instruments_%s" % InstrumentPackage.OFFSHORE)
	var fitted := menu.get_row_button("instruments_%s" % InstrumentPackage.CLASSIC)
	t.check(fitted.disabled and fitted.text == "Fitted" and "680" in modern.text and "1,480" in offshore.text,
		"[chandlery] Classic fitted; Modern Cruiser and Offshore Navigator for sale (%s / %s)" % [modern.text, offshore.text])
	await t.screenshot("i026_chandlery_electronics")
	modern.pressed.emit()  # the row's own button (the list scrolls; a click would need it in view)
	await t.frames(2)
	var price := InstrumentPackage.get_package(InstrumentPackage.MODERN).price
	t.check(GameSession.get_funds() == funds - price and GameSession.get_instrument_package().id == InstrumentPackage.MODERN
		and GameSession.owns_instrument_package(InstrumentPackage.MODERN), "[chandlery] bought and fitted for %d (funds %d -> %d)" % [price, funds, GameSession.get_funds()])
	t.check(modern.disabled and modern.text == "Fitted" and fitted.text == "Fit it (yours)" and not fitted.disabled,
		"[chandlery] the row says Fitted; Classic can be fitted again for nothing")
	t.check(app.hud.instrument_cluster.package.id == InstrumentPackage.MODERN, "[packages] the HUD follows the package fitted at once")
	app.modals.clear()
	# Too little money: refused whole, nothing taken.
	var state := GameSession.get_state_snapshot()
	state.funds = 100
	GameSession.replace_state(state)
	var refusal := GameSession.buy_instrument_package(InstrumentPackage.OFFSHORE)
	t.check(refusal.begins_with("Not enough money") and GameSession.get_funds() == 100 and not GameSession.owns_instrument_package(InstrumentPackage.OFFSHORE),
		"[packages] not enough money: refused, nothing taken (%s)" % refusal)
	state = GameSession.get_state_snapshot()
	state.funds = 20000
	GameSession.replace_state(state)
	t.check(GameSession.buy_instrument_package(InstrumentPackage.OFFSHORE) == "" and GameSession.owns_instrument_package(InstrumentPackage.MODERN),
		"[packages] buying another keeps the first (never lost)")
	# Another boat: Classic there; an owned package is fitted for nothing.
	var aboard := GameSession.get_vessel_id()
	var other: StringName = VesselCatalog.get_default().get_ids().filter(func(id: StringName) -> bool: return id != aboard)[0]
	t.check_eq(GameSession.get_instrument_package(other).id, InstrumentPackage.CLASSIC, "[packages] another boat has its own (Classic)")
	await t.board(other, app)
	funds = GameSession.get_funds()
	t.check(GameSession.fit_instrument_package(InstrumentPackage.MODERN) == "" and GameSession.get_funds() == funds
		and GameSession.get_instrument_package().id == InstrumentPackage.MODERN, "[packages] an owned package is fitted to another boat for nothing")
	GameSession.set_instrument_page(0, "heading")
	GameSession.set_instrument_page(0, "wind")  # not in display 1's slot: refused
	t.check_eq(GameSession.get_instruments().get_pages(GameSession.get_instrument_package())[0], "heading",
		"[pages] a display chooses only within its slot (the essentials stay)")
	# Save and load.
	t.check_eq(SaveManager.save_to_slot(3, GameSession.get_state_snapshot()), OK, "(setup) saved")
	var loaded := SaveManager.load_from_slot(3)
	SaveManager.delete_slot(3)  # leave no save behind (the gameplay suite expects empty slots)
	if t.check(loaded.is_ok(), "[save] loads"):
		var instruments := loaded.state.instruments
		t.check(instruments.owns(InstrumentPackage.MODERN) and instruments.owns(InstrumentPackage.OFFSHORE) and instruments.get_fitted(aboard) == InstrumentPackage.OFFSHORE
			and instruments.get_fitted(other) == InstrumentPackage.MODERN and instruments.get_pages(InstrumentPackage.get_package(InstrumentPackage.MODERN))[0] == "heading",
			"[save] owned packages, each boat's package and the pages come back (%s)" % [instruments.to_dict()])
	# An older save (no section), and a damaged one: Classic, nothing owned, never refused.
	var data := GameSession.get_state_snapshot().to_dict()
	data.erase("instruments")
	var errors: Array[String] = []
	var old := SessionState.from_dict(data, errors)
	t.check(old != null and errors.is_empty() and old.instruments.is_default() and old.instruments.get_fitted(other) == InstrumentPackage.CLASSIC,
		"[save] an older save loads with Classic and nothing owned")
	data["instruments"] = {"owned": ["imaginary", 7], "fitted": {String(other): "imaginary", "x": 3}, "pages": "lots"}
	old = SessionState.from_dict(data, errors)
	t.check(old != null and errors.is_empty() and old.instruments.is_default(), "[save] a damaged section is dropped quietly (%s)" % [errors])
	# Back to the first boat for what follows (Classic there).
	await t.board(aboard, app)
	GameSession.fit_instrument_package(InstrumentPackage.CLASSIC)


# --- 4. The cockpit -------------------------------------------------------------------------------

func _test_cockpit_on_every_boat() -> void:
	var missing: Array[String] = []
	for id: StringName in VesselCatalog.get_default().get_ids():
		await t.board(id, app)
		var deck := await _show(DECK)
		var cockpit := deck.get_node_or_null(^"CockpitInstruments") as CockpitInstruments
		var station := deck.get_node_or_null(^"Layout/Stations/Chartplotter") as Interactable
		var hull := deck._lifeline_polygon()
		if cockpit == null or station == null or station.interaction_id != &"chartplotter" or cockpit.units_at.size() != 3:
			missing.append("%s: no cockpit electronics" % id)
			continue
		for at in [cockpit.plotter_at] + Array(cockpit.units_at):
			if not Geometry2D.is_point_in_polygon(at, hull):
				missing.append("%s: %s outside the deck" % [id, at])
		var helm := deck.get_node(^"Layout/Stations/Helm") as Node2D
		if cockpit.plotter_at.distance_to(helm.position) > 200.0:
			missing.append("%s: the plotter is %d from the helm" % [id, roundi(cockpit.plotter_at.distance_to(helm.position))])
		# E at the plotter, and clicks on the units, open the focused views.
		station.interact(deck.player)
		await t.frames(2)
		if not app.modals.get_top() is PlotterView:
			missing.append("%s: E at the plotter" % id)
		app.modals.clear()
		cockpit.instruments_clicked.emit()
		await t.frames(2)
		if not app.modals.get_top() is InstrumentView:
			missing.append("%s: the instruments" % id)
		app.modals.clear()
		# The package is drawn as fitted.
		GameSession.get_instruments().add_owned(InstrumentPackage.OFFSHORE)
		GameSession.fit_instrument_package(InstrumentPackage.OFFSHORE)
		if cockpit.package.id != InstrumentPackage.OFFSHORE:
			missing.append("%s: the cockpit does not follow the package" % id)
		GameSession.fit_instrument_package(InstrumentPackage.CLASSIC)
	t.check(missing.is_empty(), "[cockpit] every boat: the plotter at the helm with its station, three instruments on deck, E and clicks open the views %s" % [missing])
	await t.board(VesselCatalog.STARTER_ID, app)


# --- 1. Authoritative values -------------------------------------------------------------------

func _test_authoritative_values() -> void:
	var data := InstrumentData.read(true)
	var here := GameSession.get_vessel_position()
	var wind := Simulation.get_wind_at(here)
	var turn := WorldMap.get_next_turn()
	var problems: Array[String] = []
	var expect := func(what: String, got: Variant, want: Variant) -> void:
		if typeof(got) == TYPE_FLOAT and not is_equal_approx(float(got), float(want)) or typeof(got) != TYPE_FLOAT and got != want:
			problems.append("%s %s != %s" % [what, got, want])
	expect.call("speed", data.speed_kn, GameSession.get_vessel_speed_kn())
	expect.call("heading", data.heading_deg, Simulation.get_current_heading())
	expect.call("wind from", data.wind_from_deg, wind.from_deg)
	expect.call("wind", data.wind_kn, wind.speed_kn)
	expect.call("gusts", data.gust_kn, wind.gust_kn)
	expect.call("wind angle", data.wind_angle, GameSession.get_propulsion().true_wind_angle)
	expect.call("to go", data.remaining_nm, GameSession.get_voyage_remaining_nm())
	expect.call("eta", data.eta, Simulation.get_eta())
	expect.call("turn", data.turn, turn)
	expect.call("destination", data.destination, PortCatalog.get_default().get_display_name(GameSession.get_voyage_destination_id()))
	expect.call("motoring", data.motoring, GameSession.is_motoring())
	var now := GameSession.get_game_time()
	for i in InstrumentData.FORECAST_HOURS.size():
		expect.call("forecast +%d h" % InstrumentData.FORECAST_HOURS[i], data.forecast[i].speed_kn,
			Simulation.get_weather_at(here, now + InstrumentData.FORECAST_HOURS[i] * 3600.0, now).speed_kn)
	# What the displays draw is the same reading.
	expect.call("speed figure", Face.speed_text(data), Loc.decimal(GameSession.get_vessel_speed_kn(), 1))
	expect.call("heading figure", Face.heading_text(data), "%03d°" % roundi(Simulation.get_current_heading()))
	var cells: Array = Face.lcd_cells("route", data)
	expect.call("route on the repeater", cells[0][1], "%s %s" % [Face.distance_text(GameSession.get_voyage_remaining_nm()), Face.cap("NM")])
	expect.call("next turn on the repeater", cells[3][1], "%03d°" % roundi(float(turn.next_course)))
	t.check(problems.is_empty(), "[values] every instrument value equals its authoritative source %s" % [problems])
	t.check(not data.values.has("depth") and data.anchor_depth_m < 0.0, "[values] no depth underway (no echo sounder is simulated)")
	# At anchor: the anchor's own depth (a game estimate).
	var state := GameSession.get_state_snapshot()
	state.anchor.active = true
	state.anchor.position = state.vessel_position
	state.anchor.depth_m = 12.0
	GameSession.replace_state(state)
	data = InstrumentData.read()
	t.check(data.anchored and data.speed_kn == 0.0 and is_equal_approx(data.anchor_depth_m, GameSession.get_anchor().depth_m)
		and "estimate" in data.get_value("depth") and data.get_value("status").contains("windlass"),
		"[values] at anchor: 0 kn, the anchor's depth (an estimate) and what to do (%s; %s)" % [data.get_value("depth"), data.get_value("status")])
	state = GameSession.get_state_snapshot()
	state.anchor = AnchorState.new()
	state.vessel_position = state.voyage.get_position()
	GameSession.replace_state(state)


# --- 2. The cluster --------------------------------------------------------------------------------

func _test_cluster() -> void:
	var cluster: InstrumentCluster = app.hud.instrument_cluster
	await t.frames(2)
	t.check(cluster.visible and app.hud.find_child("SailingPanel", true, false) == null and app.hud.find_child("ChartPlotter", true, false) == null
		and not (app.hud.find_child("RouteLabel", true, false) as Control).visible,
		"[cluster] underway: the instruments; no sailing panel, no plotter panel, no route lines drawn twice")
	# A few readings a second, never every frame.
	var reads := cluster.read_count
	var frames := [0]
	var count := func() -> void: frames[0] += 1
	t.get_tree().process_frame.connect(count)
	await t.get_tree().create_timer(1.0).timeout
	t.get_tree().process_frame.disconnect(count)
	var taken := cluster.read_count - reads
	t.check(taken >= 2 and taken <= ceili(1.0 / InstrumentCluster.REFRESH_SECONDS) + 1 and frames[0] > taken,
		"[cluster] %d readings in a second over %d frames (a few a second, not every frame)" % [taken, frames[0]])
	# In the cabin too.
	await _show(CABIN, &"from_deck")
	await t.frames(3)
	t.check(cluster.visible, "[cluster] in the cabin underway the instruments stay on the HUD")
	var wheel: Array = app.get_wheel_actions().map(func(a: Dictionary) -> StringName: return a.id)
	t.check(&"instruments" in wheel, "[cluster] the action wheel in the cabin offers the instruments (%s)" % [wheel])
	await _show(DECK)
	# Each package lays out its own units.
	for spec in [[InstrumentPackage.CLASSIC, 4], [InstrumentPackage.MODERN, 3], [InstrumentPackage.OFFSHORE, 1]]:
		GameSession.get_instruments().add_owned(spec[0])
		GameSession.fit_instrument_package(spec[0])
		await t.frames(2)
		t.check_eq(cluster.get_units().size(), spec[1], "[cluster] %s: its units" % spec[0])
	GameSession.fit_instrument_package(InstrumentPackage.CLASSIC)
	await t.frames(2)


# --- 5. Focused views ------------------------------------------------------------------------------

func _test_focused_views() -> void:
	await t.press_action(&"instruments")
	await t.frames(3)
	var view := app.modals.get_top() as InstrumentView
	if t.check(view != null, "[view] I opens the focused instrument view"):
		t.check(view.get_units().size() == 4 and view.get_key("weather") != null, "[view] Classic: three dials and the repeater with its page keys")
		await t.click(view.get_key("weather"))
		await t.frames(2)
		t.check(InstrumentView.lcd_page == "weather" and view.get_key("weather").button_pressed, "[view] the repeater shows the weather page")
		await t.screenshot("i026_view_classic_weather")
		await t.press_action(&"pause")
		await t.frames(2)
		t.check(app.modals.is_empty(), "[view] Esc closes it")
		InstrumentView.lcd_page = "route"
	# Modern: page keys per display.
	GameSession.get_instruments().add_owned(InstrumentPackage.MODERN)
	GameSession.fit_instrument_package(InstrumentPackage.MODERN)
	view = app.open_instruments()
	await t.frames(3)
	if view:
		var before := GameSession.get_instruments().get_pages(view.package)
		await t.click(view.get_key("next_1"))
		await t.frames(2)
		var after := GameSession.get_instruments().get_pages(view.package)
		t.check(after[1] != before[1] and after[1] in view.package.slot_pages(1) and app.hud.instrument_cluster.get_page(1) == after[1],
			"[view] Modern: a display's key turns its page, within its slot, and the HUD follows (%s -> %s)" % [before[1], after[1]])
		app.modals.clear()
	# Offshore: layouts.
	GameSession.get_instruments().add_owned(InstrumentPackage.OFFSHORE)
	GameSession.fit_instrument_package(InstrumentPackage.OFFSHORE)
	view = app.open_instruments()
	await t.frames(3)
	if view:
		await t.click(view.get_key("navigation"))
		await t.frames(2)
		t.check(app.hud.instrument_cluster.get_page(0) == "navigation", "[view] Offshore: its layout keys choose the layout")
		# The package selector fits another owned package.
		var selector := view.find_child("Package", true, false) as OptionButton
		t.check(selector.item_count == 3 and not selector.disabled, "[view] the selector lists the owned packages")
		selector.select(0)
		selector.item_selected.emit(0)
		await t.frames(2)
		t.check(GameSession.get_instrument_package().id == InstrumentPackage.CLASSIC and view.package.id == InstrumentPackage.CLASSIC,
			"[view] choosing one fits it to the boat at once")
		app.modals.clear()
	GameSession.set_instrument_page(0, "overview")
	GameSession.fit_instrument_package(InstrumentPackage.CLASSIC)
	await t.press_action(&"chartplotter")
	await t.frames(3)
	t.check(app.modals.get_top() is PlotterView, "[view] P opens the chartplotter, close up")
	await t.press_action(&"pause")
	await t.frames(2)
	t.check(app.modals.is_empty(), "[view] Esc closes it")


# --- 6. Layout -----------------------------------------------------------------------------------

func _screen_rect(control: Control) -> Rect2:
	return control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)


func _test_layout() -> void:
	var root := t.get_tree().root
	var original := root.size
	var problems: Array[String] = []
	for setup: Array in [[Vector2i(1280, 720), &"en", 1.0], [Vector2i(1280, 720), &"da", 1.3], [Vector2i(1024, 768), &"da", 1.0],
			[Vector2i(1024, 768), &"en", 1.3]]:
		root.size = setup[0]
		SettingsManager.set_language(setup[1])
		SettingsManager.set_ui_scale(setup[2])
		await t.frames(3)
		var label := "%dx%d %s %d%%" % [setup[0].x, setup[0].y, setup[1], roundi(float(setup[2]) * 100.0)]
		var screen := app.get_viewport().get_visible_rect().grow(1.5)
		for package_id: String in InstrumentPackage.get_ids():
			GameSession.get_instruments().add_owned(package_id)
			GameSession.fit_instrument_package(package_id)
			RadarPanel.shown = true
			await t.frames(4)
			var cluster := _screen_rect(app.hud.instrument_cluster)
			if not screen.encloses(cluster):
				problems.append("%s %s: the cluster off screen %s" % [label, package_id, cluster])
			for other in ["RoutePanel", "ClockPanel", "PassagePanel", "RadarPanel", "AreaPanel"]:
				var node := app.hud.get_node_or_null(other) as Control
				if node and node.is_visible_in_tree() and _screen_rect(node).grow(-1.0).intersects(cluster):
					problems.append("%s %s: the cluster covers %s" % [label, package_id, other])
			RadarPanel.shown = false
			for opener: Callable in [app.open_instruments, app.open_chartplotter]:
				app.modals.clear()
				opener.call()
				await t.frames(3)
				var modal := app.modals.get_top() as Control
				var panel := modal.find_child("Panel", true, false) as Control if modal else null
				if panel == null or not screen.encloses(_screen_rect(panel)):
					problems.append("%s %s: %s off screen %s" % [label, package_id, modal.name if modal else "?", _screen_rect(panel) if panel else Rect2()])
				app.modals.clear()
		# Danish captions fit their place on the small displays.
		if setup[1] == &"da":
			for page: String in ["speed", "heading", "wind", "route", "turn", "weather", "trim", "overview", "sailing", "navigation"]:
				var title := Face.page_title(page)
				if Face.fit_size(title, &"condensed", 10.5, Face.BASE * 0.6 - 10.0) < 8:
					problems.append("%s: \"%s\" too long for a display's header" % [label, title])
			if setup[0].x == 1280 and float(setup[2]) == 1.0:
				GameSession.fit_instrument_package(InstrumentPackage.MODERN)
				await t.frames(4)
				await t.screenshot("i026_instruments_da")
	t.check(problems.is_empty(), "[layout] the instruments and their views fit beside the HUD at 1280x720 and 1024x768, 100 %% and 130 %%, English and Danish %s" % [problems])
	GameSession.fit_instrument_package(InstrumentPackage.CLASSIC)
	SettingsManager.set_ui_scale(1.0)
	SettingsManager.set_language(&"en")
	root.size = original
	await t.frames(2)
