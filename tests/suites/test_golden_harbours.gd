extends RefCounted
## Golden Harbour Moments: the first arrival in a harbour with a picture is a
## small illustrated travel memory (HarbourMoment) in the notice column, lit
## for the hour; a known harbour keeps the quiet card; loading a game or going
## below shows nothing; a click puts it away; nothing pauses or blocks; the
## painting's own windows are found once and cached; English and Danish.
## Screenshots: day, dusk and night, three different harbour pictures, both
## languages, in the real game.

const APP_SCENE := preload("res://src/app/app.tscn")

var t: Node
var app: Node


func run(runner: Node) -> void:
	t = runner
	_test_light_and_windows()
	Simulation.auto_advance = false
	var root := t.get_tree().root
	var original := root.size
	root.size = Vector2i(1280, 720)
	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	await _test_first_and_repeat()
	await _test_quiet_places()
	await _test_dusk_and_night()
	app.queue_free()
	await t.frames(2)
	root.size = original
	SettingsManager.set_language(&"en")
	Simulation.auto_advance = true


func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)


func _test_light_and_windows() -> void:
	t.check(HarbourMoment.light_of(30.0, true) == &"day" and HarbourMoment.light_of(3.0, true) == &"dawn" and HarbourMoment.light_of(3.0, false) == &"dusk"
		and HarbourMoment.light_of(-10.0, false) == &"night", "[light] day, dawn, dusk and night from the sun's height and the morning")
	var looks := HarbourLooks.get_default()
	var counts := {}
	var pictures := {}
	for port: StringName in [&"helsingor", &"symi", &"bequia", &"valletta"]:
		pictures[port] = looks.picture_for(port)
	var start := Time.get_ticks_usec()
	for port: StringName in pictures:
		counts[port] = HarbourMoment.window_spots(pictures[port]).size()
	var first_ms := float(Time.get_ticks_usec() - start) / 1000.0
	start = Time.get_ticks_usec()
	for port: StringName in pictures:
		HarbourMoment.window_spots(pictures[port])
	var cached_ms := float(Time.get_ticks_usec() - start) / 1000.0
	t.check(counts.values().filter(func(n: int) -> bool: return n >= 6).size() >= 3 and counts.values().all(func(n: int) -> bool: return n <= HarbourMoment.MAX_WINDOWS),
		"[windows] the paintings' own windows are found where they are painted dark (%s; Symi's are pale: it keeps the warm light and the lanterns)" % [counts])
	t.check(first_ms < 400.0 and cached_ms < 2.0, "[performance] finding the windows of four pictures %.0f ms once, then %.2f ms (cached)" % [first_ms, cached_ms])


## Starts at `from` at `hour_utc`, sails to `to` and arrives (the real voyage).
func _arrive(from: StringName, to: StringName, hour_utc: float) -> void:
	GameSession.start_new_session()
	var catalog := PortCatalog.get_default()
	var state := GameSession.get_state_snapshot()
	state.location_id = from
	state.vessel_position = catalog.get_port(from).get_geo_position()
	state.game_time = state.game_time - fposmod(state.game_time, 86400.0) + hour_utc * 3600.0
	GameSession.replace_state(state)
	app.modals.clear()
	app.toasts.clear()
	app._show_current_boat_area()
	await _settle()
	GameSession.plan_route_to(to)
	GameSession.depart()
	var guard := 0
	while GameSession.is_underway() and guard < 400:
		Simulation.advance(600.0, true)
		guard += 1
	await _settle()
	await t.frames(6)
	# The interface's day/night change eases over a few real seconds after the jump in time.
	await t.wait_until(func() -> bool: return UiTheme.blend == UiTheme._target_blend(), 6.0)


## When `hours` of sailing from `from` to `to` take, so an arrival can be set for an hour.
func _hop_hours(from: StringName, to: StringName) -> float:
	GameSession.start_new_session()
	var state := GameSession.get_state_snapshot()
	state.location_id = from
	state.vessel_position = PortCatalog.get_default().get_port(from).get_geo_position()
	GameSession.replace_state(state)
	GameSession.plan_route_to(to)
	GameSession.depart()
	var start := GameSession.get_game_time()
	var guard := 0
	while GameSession.is_underway() and guard < 400:
		Simulation.advance(600.0, true)
		guard += 1
	return (GameSession.get_game_time() - start) / 3600.0


func _moments() -> Array[Node]:
	return app.toasts.get_children().filter(func(n: Node) -> bool: return n is HarbourMoment and not n.is_queued_for_deletion())


func _cards() -> Array[Node]:
	return app.toasts.get_children().filter(func(n: Node) -> bool: return n.name.begins_with("ArrivalCard") and not n.is_queued_for_deletion())


func _test_first_and_repeat() -> void:
	SettingsManager.set_language(&"en")
	await _arrive(&"copenhagen", &"helsingor", 9.0)
	var moments := _moments()
	if not t.check(moments.size() == 1, "[first visit] arriving in Helsingør for the first time: a Golden Harbour Moment (%d)" % moments.size()):
		return
	var moment := moments[0] as HarbourMoment
	var texts := " ".join(moment.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text))
	t.check(texts.contains("Helsingør") and texts.contains("First visit") and texts.contains("New harbour in the Captain's Log"),
		"[first visit] the name, \"First visit\" and the Captain's Log line on the card")
	t.check(not Array(app.toasts.get_messages()).any(func(m: String) -> bool: return m.begins_with("New harbour in the Captain's Log")),
		"[first visit] no separate Log notice beside it (one card, not two)")
	t.check(app.modals.is_empty() and not t.get_tree().paused, "[first visit] nothing paused, no window opened")
	t.check(moment.light_of(moment.elevation, true) == &"day", "[light] arrived by day")
	await t.screenshot("golden_helsingor_day_en")
	# A click puts it away.
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	moment._gui_input(click)
	await t.frames(3)
	await t.wait_until(func() -> bool: return _moments().is_empty(), 2.0)
	t.check(_moments().is_empty(), "[dismiss] a click puts it away")
	# Sailing back to a known harbour: the quiet small card.
	app.toasts.clear()
	GameSession.plan_route_to(&"copenhagen")
	GameSession.depart()
	var guard := 0
	while GameSession.is_underway() and guard < 400:
		Simulation.advance(600.0, true)
		guard += 1
	await _settle()
	await t.frames(4)
	t.check(_moments().is_empty() and _cards().size() == 1, "[return] back in Copenhagen, a known harbour: the small card only")
	# And Helsingør again: known now.
	app.toasts.clear()
	GameSession.plan_route_to(&"helsingor")
	GameSession.depart()
	guard = 0
	while GameSession.is_underway() and guard < 400:
		Simulation.advance(600.0, true)
		guard += 1
	await _settle()
	await t.frames(4)
	t.check(_moments().is_empty(), "[return] Helsingør a second time: no second moment")


func _test_quiet_places() -> void:
	# Loading a game moored in a harbour never visited before (in this game): no moment.
	GameSession.start_new_session()
	var state := GameSession.get_state_snapshot()
	state.location_id = &"symi"
	state.vessel_position = PortCatalog.get_default().get_port(&"symi").get_geo_position()
	GameSession.replace_state(state)
	t.check_eq(SaveManager.save_to_slot(3, GameSession.get_state_snapshot()), OK, "(setup) saved in Symi")
	app.toasts.clear()
	app.load_slot(3)
	await _settle()
	await t.frames(4)
	t.check(_moments().is_empty(), "[load] loading a game moored in Symi: no moment (not an arrival)")
	app._on_area_change_requested(&"interior", &"from_deck")
	await _settle()
	app._on_area_change_requested(&"exterior", &"start")
	await _settle()
	t.check(_moments().is_empty(), "[cabin] going below and back on deck: no moment")
	SaveManager.delete_slot(3)


func _test_dusk_and_night() -> void:
	# Symi at dusk, in Danish: a special harbour with its own art.
	var hours := _hop_hours(&"marmaris", &"symi")
	SettingsManager.set_language(&"da")
	await _arrive(&"marmaris", &"symi", fposmod(17.4 - hours, 24.0))
	var moments := _moments()
	if t.check(moments.size() == 1, "[special] Symi for the first time: a moment (%.1f h hop)" % hours):
		var moment := moments[0] as HarbourMoment
		var stamp := (moment.find_child("Stamp", true, false) as Label).text
		t.check(moment.special and stamp.contains("Særlig havn") and stamp.contains("Første besøg"),
			"[dansk] the stamp in Danish: %s" % stamp)
		t.check(moment.light_of(moment.elevation, false) in [&"dusk", &"dawn"], "[light] arrived around dusk (sun %.1f°)" % moment.elevation)
		var screen := app.get_viewport().get_visible_rect()
		var rect: Rect2 = moment.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, moment.size)
		t.check(screen.encloses(rect), "[layout] the card lies inside the screen (%s)" % rect)
		await t.screenshot("golden_symi_dusk_da")
	# Bequia at night, in English.
	hours = _hop_hours(&"castries", &"bequia")
	SettingsManager.set_language(&"en")
	await _arrive(&"castries", &"bequia", fposmod(3.0 - hours, 24.0))
	moments = _moments()
	if t.check(moments.size() == 1, "[first visit] Bequia for the first time: a moment (%.1f h hop)" % hours):
		var moment := moments[0] as HarbourMoment
		t.check(moment.light_of(moment.elevation, false) == &"night", "[light] arrived at night (sun %.1f°): windows lit" % moment.elevation)
		await t.screenshot("golden_bequia_night_en")
