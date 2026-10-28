extends RefCounted
## Operation Steady Hands: the interface stays put, inside the screen, closable
## and translated.
##
## 1. The weather warning never moves Trip Details (the sailing panel): shown,
##    hidden, updated with short and long texts, in English and Danish, by
##    day and night, with Trip Details collapsed and expanded.
## 2. A sweep over every window the game opens from its own entry points,
##    moored and underway, in English and Danish, at interface size 100 %
##    and 130 %. Each window must:
##    - lie inside the screen (every visible control);
##    - close with Esc (handle_back), except the documented exemptions;
##    - show no leftover placeholder ("%s", "{action}");
##    - show no English text that has a Danish translation while Danish is chosen.
## 3. The HUD's own pieces stay inside the screen and do not cover each other
##    (named pairs only: some layers overlap on purpose, e.g. a modal's dim
##    backdrop, the toasts and the time passage).
## 4. Dusk and dawn: the interface changes mood once, at the middle of the
##    twilight, instead of sitting half-way (where text and panel were the
##    same grey); text never mixes its day and night colours.
## Overlap is not checked blindly; each check names what it protects.

const APP_SCENE := preload("res://src/app/app.tscn")
## Pixels of tolerance (rounding of scaled layouts).
const EPS := 1.5
## [window size, language, interface size]: 16:9 at 100 % and 130 % (the
## smallest canvas, 1477 x 831), 4:3 and 21:9.
const SWEEPS := [[Vector2i(1280, 720), &"en", 1.0], [Vector2i(1280, 720), &"da", 1.0], [Vector2i(1280, 720), &"en", 1.3],
	[Vector2i(1280, 720), &"da", 1.3], [Vector2i(1024, 768), &"da", 1.0], [Vector2i(2560, 1080), &"da", 1.0]]
## Screenshots of the windows whose fixes matter most.
const SHOTS := {"1280x720 da 100%|Settings": "steady_settings_1280x720_da", "1280x720 en 130%|Settings": "steady_settings_1280x720_en_130",
	"1280x720 en 130%|Boatyard": "steady_boatyard_1280x720_en_130", "1280x720 da 100%|Make it home": "steady_make_it_home_1280x720_da"}
## Windows that intentionally do not close with Esc (with the reason).
const NO_ESC := {"LanguagePicker": "first launch: only a language choice closes it (it has a button per language)"}

var t: Node
var app: Node
var findings: Array[String] = []


func run(runner: Node) -> void:
	t = runner
	Simulation.auto_advance = false
	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	# A real window: the test runner's own window is a 64 px square, which the
	# "expand" stretch turns into a 1920 x 1920 canvas. Every 16:9 size
	# (1280 x 720, 1600 x 900, 1920 x 1080) gives the same 1920 x 1080 canvas.
	var root := t.get_tree().root
	var original := root.size
	root.size = Vector2i(1280, 720)
	await t.frames(3)
	await _test_weather_does_not_move_trip_details()
	await _test_long_texts()
	await _test_transitions()
	await _test_dusk_readability()
	for setup: Array in SWEEPS:
		root.size = setup[0]
		SettingsManager.set_language(setup[1])
		SettingsManager.set_ui_scale(setup[2])
		await t.frames(3)
		await _sweep("%dx%d %s %d%%" % [setup[0].x, setup[0].y, setup[1], roundi(float(setup[2]) * 100.0)])
	SettingsManager.set_ui_scale(1.0)
	SettingsManager.set_language(&"en")
	root.size = original
	app.modals.clear()
	await t.frames(2)
	app.queue_free()
	await t.frames(2)
	Simulation.auto_advance = true  # as the other suites leave it


func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)


func _start(underway: bool, area: StringName, hour_utc := 10.0) -> void:
	GameSession.start_new_session()
	var state := GameSession.get_state_snapshot()
	state.game_time = state.game_time - fposmod(state.game_time, 86400.0) + hour_utc * 3600.0
	state.funds = 60000
	GameSession.replace_state(state)
	if underway:
		GameSession.plan_route_to(&"helsingor")
		GameSession.depart()
	app.modals.clear()
	app._show_current_boat_area()
	await _settle()
	app._on_area_change_requested(area, &"start" if area == &"exterior" else &"from_deck")
	await _settle()


func _viewport_rect() -> Rect2:
	return app.get_viewport().get_visible_rect()


## The control's rectangle on the screen (through its UI-scale layer).
static func screen_rect(control: Control) -> Rect2:
	var xf := control.get_global_transform_with_canvas()
	return xf * Rect2(Vector2.ZERO, control.size)


func _inside(rect: Rect2) -> bool:
	var screen := _viewport_rect().grow(EPS)
	return screen.encloses(rect)


# --- 1. The weather warning and Trip Details ------------------------------------------------------------

func _test_weather_does_not_move_trip_details() -> void:
	var hud: Control = app.hud
	var texts := [
		"Gale warning: wind rising to 35 kn within 3 h.",
		"Storm warning for the area ahead: southwesterly 45 kn and higher seas from tonight. Consider a harbour or a sheltered anchorage before dark; the next harbour on the course is Helsingør, 18 nm.",
		"Kulingvarsel: vinden tiltager til 35 knob inden for 3 timer.",
		"Stormvarsel for området forude: sydvestlig 45 knob og højere sø fra i aften. Overvej en havn eller en beskyttet ankerplads før mørkets frembrud; næste havn på kursen er Helsingør, 18 sm.",
	]
	for language: StringName in [&"en", &"da"]:
		SettingsManager.set_language(language)
		for hour in [10.0, 23.0]:
			await _start(true, &"exterior", hour)
			for collapsed in [false, true]:
				SailingPanel.collapsed = collapsed
				await t.frames(3)
				var trip: Control = hud.sailing_panel
				var route := hud.get_node("RoutePanel") as Control
				var warning := hud.get_node("WarningPanel") as Control
				if not t.check(trip.visible, "(setup) Trip Details shows underway"):
					return
				var before := screen_rect(trip)
				var moved: Array[String] = []
				var overlaps: Array[String] = []
				for round in 3:
					for text in texts:
						hud.show_warning(text)
						await t.frames(2)
						if not screen_rect(trip).is_equal_approx(before):
							moved.append("shown: %s" % [screen_rect(trip)])
						var w := screen_rect(warning)
						if w.intersects(screen_rect(trip).grow(-1.0)) or w.intersects(screen_rect(route).grow(-1.0)):
							overlaps.append(text.left(20))
						if not _inside(w):
							overlaps.append("off screen: %s" % [w])
					hud.hide_warning()
					await t.frames(2)
					if not screen_rect(trip).is_equal_approx(before):
						moved.append("hidden: %s" % [screen_rect(trip)])
				t.check(moved.is_empty(), "[trip details] %s, %02d:00, %s: the weather warning shown, updated and hidden 12 times never moves Trip Details %s" % [
					language, int(hour), "collapsed" if collapsed else "expanded", moved])
				t.check(overlaps.is_empty(), "[trip details] %s, %02d:00, %s: the warning never covers Trip Details or the route panel, and stays on screen %s" % [
					language, int(hour), "collapsed" if collapsed else "expanded", overlaps])
				if language == &"da" and hour == 10.0 and not collapsed:
					hud.show_warning(texts[3])
					await t.frames(2)
					await t.screenshot("steady_trip_details_with_warning_da")
					hud.hide_warning()
	SailingPanel.collapsed = false
	SettingsManager.set_language(&"en")


# --- 2. The window sweep ----------------------------------------------------------------------------------

## [label, underway, area, opener]
func _openers() -> Array:
	return [
		["Action wheel (cabin)", false, &"interior", func() -> void: app.open_action_wheel()],
		["Sleep", false, &"interior", func() -> void: app.open_sleep_menu()],
		["Provisions", false, &"interior", func() -> void: app.open_provisions()],
		["Galley", false, &"interior", func() -> void: app.open_cooking()],
		["Make it home", false, &"interior", func() -> void: app.open_cabin_home()],
		["Trophies", false, &"interior", func() -> void: app.open_trophies()],
		["Remote work", false, &"interior", func() -> void: app.open_work_menu()],
		["Postcards", false, &"interior", func() -> void: app.open_postcards()],
		["Little game", false, &"interior", func() -> void: app.open_game_dev()],
		["Action wheel (deck)", false, &"exterior", func() -> void: app.open_action_wheel()],
		["Grocery", false, &"exterior", func() -> void: app.open_grocery()],
		["Fishmonger", false, &"exterior", func() -> void: app.open_fishmonger()],
		["Chandlery", false, &"exterior", func() -> void: app.open_chandlery()],
		["Sailmaker", false, &"exterior", func() -> void: app.open_sailmaker()],
		["Go ashore", false, &"exterior", func() -> void: app.open_go_ashore()],
		["Boatyard", false, &"exterior", func() -> void: app.open_boatyard()],
		["Boat care", false, &"exterior", func() -> void: app.open_boat_care()],
		["Haul-out", false, &"exterior", func() -> void: app.open_haul_out()],
		["Fishing", false, &"exterior", func() -> void: app.open_fishing()],
		["Pause menu", false, &"exterior", func() -> void: app.open_pause_menu()],
		["Captain's Log", false, &"exterior", func() -> void: app.open_captains_log()],
		["Settings", false, &"exterior", func() -> void: app.open_settings()],
		["Save", false, &"exterior", func() -> void: app.open_save_menu()],
		["Load", false, &"exterior", func() -> void: app.open_load_menu()],
		["Handbook", false, &"exterior", func() -> void: app.open_handbook()],
		["Difficulty", false, &"exterior", func() -> void: app.modals.push(DifficultyMenu.new())],
		["Scrapbook", false, &"exterior", func() -> void: app.modals.push(ScrapbookMenu.new())],
		["Confirm dialog", false, &"exterior", func() -> void: app.modals.confirm(Loc.t("Load this game?"), Loc.t("Progress since your last save will be lost."), "Load")],
		["Action wheel (underway)", true, &"exterior", func() -> void: app.open_action_wheel()],
		["Sail trim", true, &"exterior", func() -> void: app.open_sail_trim()],
		["Anchor", true, &"exterior", func() -> void: app.open_anchor()],
		["Fishing (underway)", true, &"exterior", func() -> void: app.open_fishing()],
		["Publish", false, &"exterior", func() -> void: app.open_publish_menu()],
		["VHF call", true, &"exterior", func() -> void:
			var dialog := VhfDialog.new()
			for slot in 200:
				dialog.call = VhfRadio.call_for_slot(1.79e9, slot, 3, true)
				if dialog.call.get("kind") == VhfRadio.KIND_ASSIST:
					break
			app.modals.push(dialog)],
	]


func _sweep(label: String) -> void:
	var context := ""
	var failed: Array[String] = []
	var not_opened: Array[String] = []
	for opener: Array in _openers():
		var key := "%s %s" % [opener[1], opener[2]]
		if key != context:
			context = key
			await _start(bool(opener[1]), opener[2])
		app.modals.clear()
		await t.frames(1)
		(opener[3] as Callable).call()
		await t.frames(3)
		var modal: ModalPanel = app.modals.get_top()
		if modal == null:
			not_opened.append(String(opener[0]))
			continue
		var problems := check_window(modal)
		if SHOTS.has("%s|%s" % [label, opener[0]]):
			await t.screenshot(SHOTS["%s|%s" % [label, opener[0]]])
		# Esc closes it.
		var kind := String(modal.get_script().get_global_name())
		var id := modal.get_instance_id()
		var still_open := func() -> bool:
			return app.modals.get_all().any(func(m: ModalPanel) -> bool: return is_instance_valid(m) and m.get_instance_id() == id)
		if not NO_ESC.has(kind):
			for i in 3:
				if not still_open.call():
					break
				app.modals.handle_back()
				await t.frames(2)
				var top: ModalPanel = app.modals.get_top()
				if top is ConfirmDialog and top.get_instance_id() != id:
					(top as ConfirmDialog).handle_back()
					await t.frames(2)
			if still_open.call():
				problems.append("Esc does not close it")
		if not problems.is_empty():
			failed.append("%s: %s" % [opener[0], "; ".join(problems)])
	app.modals.clear()
	t.check(not_opened.size() <= 2, "[sweep %s] opened %d of %d windows from the game's own entry points (not here: %s)" % [
		label, _openers().size() - not_opened.size(), _openers().size(), not_opened])
	t.check(failed.is_empty(), "[sweep %s] every window lies inside the screen, closes with Esc and shows no raw or untranslated text%s" % [
		label, "" if failed.is_empty() else "\n      " + "\n      ".join(failed)])
	await _check_hud(label)
	await _check_screens(label)
	await _check_no_hidden_click_catchers(label)


## The problems of one open window (empty when it is fine).
func check_window(modal: Node) -> Array[String]:
	var problems: Array[String] = []
	var outside: Array[String] = []
	var raw: Array[String] = []
	var english: Array[String] = []
	var danish := SettingsManager.get_language() == &"da"
	for node in modal.find_children("*", "Control", true, false):
		var control := node as Control
		if not control.is_visible_in_tree() or control.name == &"Dim":
			continue
		# Interface only: controls drawn in the world under the camera (the
		# chart's own artwork) are not interface and may exceed the screen.
		if control.get_canvas_layer_node() == null:
			continue
		if _inside_scroll(control, modal):
			continue
		var rect := screen_rect(control)
		if rect.size.x > 0.5 and rect.size.y > 0.5 and not _inside(rect):
			outside.append("%s %s" % [control.name, rect])
		var text := _text_of(control)
		if text.is_empty():
			continue
		if text.contains("%s") or text.contains("%d") or (text.contains("{") and text.contains("}")):
			raw.append("%s \"%s\"" % [control.name, text.left(40)])
		if danish and not control.can_auto_translate() and Loc.t(text) != text:
			english.append("%s \"%s\"" % [control.name, text.left(40)])
		elif danish:
			var shown := Loc.t(text) if control.can_auto_translate() else text
			var phrase := english_phrase(shown)
			if not phrase.is_empty():
				english.append("%s \"%s\" in \"%s\"" % [control.name, phrase, shown.left(50)])
	if not outside.is_empty():
		problems.append("outside the screen: %s" % ", ".join(outside.slice(0, 4)))
	if not raw.is_empty():
		problems.append("raw placeholder: %s" % ", ".join(raw.slice(0, 4)))
	if not english.is_empty():
		problems.append("English while Danish is chosen: %s" % ", ".join(english.slice(0, 4)))
	return problems


## Controls inside a scroll area are checked as the scroll area itself.
func _inside_scroll(control: Control, top: Node) -> bool:
	var node := control.get_parent()
	while node and node != top:
		if node is ScrollContainer or node is ItemList or node is RichTextLabel:
			return true
		node = node.get_parent()
	return false


static func _text_of(control: Control) -> String:
	if control is Label:
		return (control as Label).text
	if control is Button:
		return (control as Button).text
	return ""


# --- 3. The HUD ---------------------------------------------------------------------------------------------

## HUD pieces that must never cover each other (when both show).
const HUD_PAIRS := [["RoutePanel", "SailingPanel"], ["RoutePanel", "WarningPanel"], ["SailingPanel", "WarningPanel"],
	["SailingPanel", "PassagePanel"], ["WarningPanel", "PassagePanel"], ["ClockPanel", "RoutePanel"], ["ClockPanel", "AreaPanel"],
	["PromptPanel", "Controls"], ["ChartPlotter", "Controls"], ["RadarPanel", "Controls"], ["AreaPanel", "HatBadge"],
	["PromptPanel", "RadarPanel"], ["PromptPanel", "ChartPlotter"], ["ChartPlotter", "RadarPanel"], ["PromptPanel", "PassagePanel"]]


func _check_hud(label: String) -> void:
	var problems: Array[String] = []
	for underway in [false, true]:
		await _start(underway, &"exterior")
		app.hud.show_warning(Loc.t("Gale warning: wind rising to 35 kn within 3 h."))
		ChartPlotter.shown = true
		RadarPanel.shown = true
		await t.frames(4)
		var pieces := {}
		for node in app.hud.get_children():
			var control := node as Control
			if control and control.is_visible_in_tree() and control.size.x > 1.0:
				pieces[String(control.name)] = screen_rect(control)
				if not _inside(pieces[String(control.name)]):
					problems.append("%s off screen %s" % [control.name, pieces[String(control.name)]])
		if SettingsManager.get_language() == &"da":
			for node in app.hud.find_children("*", "Label", true, false):
				var text_label := node as Label
				# What is on screen: Godot translates a whole label text by itself.
				var shown := Loc.t(text_label.text) if text_label.can_auto_translate() else text_label.text
				var phrase := english_phrase(shown)
				if text_label.is_visible_in_tree() and not phrase.is_empty():
					problems.append("%s shows English \"%s\" in \"%s\"" % [node.name, phrase, shown])
		if underway:
			await t.screenshot("steady_hud_" + label.replace(" ", "_").replace("%", ""))
		for pair: Array in HUD_PAIRS:
			if pieces.has(pair[0]) and pieces.has(pair[1]) and (pieces[pair[0]] as Rect2).grow(-1.0).intersects(pieces[pair[1]]):
				problems.append("%s covers %s" % pair)
		app.hud.hide_warning()
		ChartPlotter.shown = false
		RadarPanel.shown = false
	t.check(problems.is_empty(), "[hud %s] moored and underway, with a warning, the chart plotter and the radar: all inside the screen, no named pair covers the other %s" % [
		label, problems])


# --- 4. Screens: main menu, new game, language, chart, dream map --------------------------------------------

func _check_screens(label: String) -> void:
	var problems: Array[String] = []
	app.modals.clear()
	app.show_main_menu()
	await _settle()
	problems.append_array(_prefixed("Main menu", check_window(app.router.current_screen)))
	for entry: Array in [["New game", func() -> void: app.open_new_game_menu()], ["Language", func() -> void: app.show_language_picker()],
			["Load (main menu)", func() -> void: app.open_load_menu()]]:
		app.modals.clear()
		await t.frames(1)
		(entry[1] as Callable).call()
		await t.frames(3)
		if app.modals.get_top():
			problems.append_array(_prefixed(entry[0], check_window(app.modals.get_top())))
	app.modals.clear()
	await _start(false, &"exterior")
	app.open_chart()
	await _settle()
	await t.frames(3)
	problems.append_array(_prefixed("Chart", check_window(app.router.current_screen)))
	await _start(false, &"interior")
	app.open_dream_map()
	await _settle()
	await t.frames(3)
	problems.append_array(_prefixed("Dream map", check_window(app.router.current_screen)))
	await _start(false, &"exterior")
	t.check(problems.is_empty(), "[screens %s] main menu, new game, language, load, chart and dream map lie inside the screen, translated%s" % [
		label, "" if problems.is_empty() else "\n      " + "\n      ".join(problems)])


static func _prefixed(prefix: String, problems: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for problem in problems:
		out.append("%s: %s" % [prefix, problem])
	return out


## In play with nothing open, no visible control that catches the mouse may
## cover a large part of the screen (an invisible overlay would swallow the
## clicks meant for the boat, the HUD or the chart).
func _check_no_hidden_click_catchers(label: String) -> void:
	var catchers: Array[String] = []
	for underway in [false, true]:
		await _start(underway, &"exterior")
		var screen := _viewport_rect()
		for node in app.find_children("*", "Control", true, false):
			var control := node as Control
			if not control.is_visible_in_tree() or control.mouse_filter != Control.MOUSE_FILTER_STOP:
				continue
			var rect := screen_rect(control).intersection(screen)
			if rect.get_area() > screen.get_area() * 0.2:
				catchers.append("%s (%s)" % [control.get_path(), rect])
	t.check(catchers.is_empty(), "[clicks %s] nothing invisible or oversized catches the mouse over the game %s" % [label, catchers])


# --- 5. Long names and messages --------------------------------------------------------------------------------

## The longest harbour name in the game, long notifications and an arrival
## card, in both languages at 130 %: everything stays on screen.
func _test_long_texts() -> void:
	SettingsManager.set_ui_scale(1.3)
	for language: StringName in [&"en", &"da"]:
		SettingsManager.set_language(language)
		GameSession.start_new_session()
		var state := GameSession.get_state_snapshot()
		state.location_id = &"les_sables"
		state.vessel_position = PortCatalog.get_default().get_port(&"les_sables").get_geo_position()
		GameSession.replace_state(state)
		GameSession.plan_route_to(&"boulogne")
		GameSession.depart()
		app.modals.clear()
		app._show_current_boat_area()
		await _settle()
		app.hud.show_warning(Loc.t("Gale warning: wind rising to 35 kn within 3 h."))
		for i in 3:
			app.notify(Loc.t("You were woken after %s by a call for assistance on the radio. It is %s.%s") % ["7 h 59 min",
				Simulation.format_game_time(GameSession.get_game_time()), Loc.t("  Time is still paused.")])
		app.toasts.show_card(Loc.t("Arrived in %s.") % "Les Sables-d'Olonne", PortCatalog.get_default().get_port(&"les_sables").get_description(),
			HarbourLooks.get_default().picture_for(&"les_sables"))
		await t.frames(4)
		var outside: Array[String] = []
		for node in app.hud.get_children() + app.toasts.get_children():
			var control := node as Control
			if control and control.is_visible_in_tree() and control.size.x > 1.0 and not _inside(screen_rect(control)):
				outside.append("%s %s" % [control.name, screen_rect(control)])
		t.check(outside.is_empty(), "[long texts %s 130%%] bound for Les Sables-d'Olonne / Boulogne-sur-Mer with a warning, three long notices and an arrival card: all on screen %s" % [
			language, outside])
		if language == &"da":
			await t.screenshot("steady_long_texts_da_130")
		app.hud.hide_warning()
		for toast in app.toasts.get_children():
			toast.queue_free()
	SettingsManager.set_ui_scale(1.0)
	SettingsManager.set_language(&"en")


# --- 6. Changes of context under an open window -----------------------------------------------------------------

func _test_transitions() -> void:
	# Sail trim open, then the boat is in harbour: Esc still closes it, and
	# the underway-only pieces go away.
	await _start(true, &"exterior")
	RadarPanel.shown = true
	app.modals.push(SailTrimPanel.new())
	await t.frames(2)
	var opened := app.modals.get_top() is SailTrimPanel
	var state := GameSession.get_state_snapshot()
	state.voyage = null
	state.vessel_status = SessionState.STATUS_MOORED
	state.location_id = &"helsingor"
	GameSession.replace_state(state)
	await t.frames(3)
	app.modals.handle_back()
	await t.frames(2)
	t.check(opened and app.modals.is_empty() and not app.hud.sailing_panel.visible and not app.hud.radar_panel.visible,
		"[context] sail trim open when the boat is moored closes (by itself or with Esc); Trip Details and the radar go away (opened %s, open %d, trip %s, radar %s, underway %s)" % [
			opened, app.modals.depth(), app.hud.sailing_panel.visible, app.hud.radar_panel.visible, GameSession.is_underway()])
	RadarPanel.shown = false
	# The wheel open when a warning arrives: both close their own way.
	await _start(true, &"exterior")
	app.open_action_wheel()
	await t.frames(2)
	app.hud.show_warning("Gale warning")
	await t.frames(2)
	app.modals.handle_back()
	await t.frames(2)
	var dismiss := app.hud.find_child("WarningDismissButton", true, false) as Button
	dismiss.pressed.emit()
	await t.frames(2)
	t.check(app.modals.is_empty() and not app.hud.is_warning_visible(), "[context] a warning arriving over the Q wheel: the wheel closes with Esc, the warning with Dismiss")
	# Settings open while the language changes: still on screen.
	app.open_settings()
	await t.frames(2)
	SettingsManager.set_language(&"da")
	await t.frames(3)
	var problems := check_window(app.modals.get_top())
	SettingsManager.set_language(&"en")
	await t.frames(2)
	t.check(problems.is_empty(), "[context] Settings stays on screen when the language changes while it is open %s" % [problems])
	app.modals.clear()
	# Saving and loading with a window open: the loaded game starts clean.
	await _start(false, &"exterior")
	t.check_eq(SaveManager.save_to_slot(3, GameSession.get_state_snapshot()), OK, "(setup) saved")
	app.open_pause_menu()
	await t.frames(2)
	app.load_slot(3)
	await _settle()
	t.check(app.modals.is_empty() and app.is_in_gameplay() and not app.hud.is_warning_visible(), "[context] loading a game from the menu leaves no window or warning behind")
	SaveManager.delete_slot(3)


# --- 7. Readable through dusk and dawn ----------------------------------------------------------------------------

func _test_dusk_readability() -> void:
	# A whole day moored, in ten-minute steps: the theme's target is always
	# plainly day or night, and it changes once each way.
	await _start(false, &"exterior", 0.0)
	UiTheme.set_blend(UiTheme._target_blend(), true)
	var in_between := 0
	var switches := 0
	for step in 144:
		Simulation.advance(600.0, true)
		var target := UiTheme._target_blend()
		if target not in [0.0, 1.0]:
			in_between += 1
		if target != UiTheme.blend:
			switches += 1
			UiTheme.set_blend(target, true)
	t.check(in_between == 0 and switches == 2, "[dusk] over a day the interface is day or night, never parked half-way, and changes twice (%d half-way, %d changes)" % [
		in_between, switches])
	# During the few seconds of the change itself, text stays readable on its panel.
	var worst := 99.0
	for i in 11:
		var night := i / 10.0
		for pair: Array in [[&"ink", &"surface"], [&"ink", &"surface_hud"], [&"ink", &"sidebar"], [&"button_text", &"button"], [&"action_text", &"action"]]:
			worst = minf(worst, _contrast(UiTheme.color_at(pair[0], night), UiTheme.color_at(pair[1], night)))
	# (The lowest is the instant text changes over, half-way through a fade of
	# a few seconds; it was 1.0:1 there, and for the whole twilight.)
	t.check(worst >= 2.5, "[dusk] text on panels and buttons all through the change: at least %.1f:1" % worst)
	UiTheme.set_blend(UiTheme._target_blend(), true)


static func _contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _luminance(c: Color) -> float:
	var parts := [c.r, c.g, c.b].map(func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4))
	return 0.2126 * parts[0] + 0.7152 * parts[1] + 0.0722 * parts[2]


static var _english := PackedStringArray()


## A phrase of at least two words that has a Danish translation and appears
## in `text` in English while its translation does not ("" when none). For
## texts built from several pieces, which the window check cannot see.
static func english_phrase(text: String) -> String:
	if _english.is_empty():
		var danish := TranslationServer.get_translation_object("da")
		for message in danish.get_message_list():
			var english := String(message)
			if english.count(" ") >= 1 and english.length() >= 8 and not english.contains("%") and danish.get_message(english) != english:
				_english.append(english)
	for english in _english:
		if text.contains(english) and not text.contains(Loc.t(english)):
			return english
	return ""
