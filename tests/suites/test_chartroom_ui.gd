extends RefCounted
## The Captain's Chartroom UI pass: one shared theme with two moods.
##   - the theme is built from role tokens, with the variations the screens use;
##   - Always day / Always night / Automatic (the game's daylight, not the OS
##     clock), eased over a few seconds, stored in settings (not the save);
##   - a mood change does not close or reset an open window;
##   - the HUD shows less (no empty route panel, no duplicate lines underway)
##     without hiding warnings;
##   - the chart keeps its functions with a simpler course panel;
##   - fishing's timing dial is shown and unobstructed; boat care and the
##     settings window open; the tint adapter follows the mood.

const APP_SCENE := preload("res://src/app/app.tscn")

var t: Node
var app: Node


func run(runner: Node) -> void:
	t = runner
	Simulation.auto_advance = false
	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	_test_theme_foundation()
	await _test_modes_and_settings()
	app.start_new_game()
	await _settle()
	await _test_automatic_follows_daylight()
	await _test_open_window_survives()
	await _test_hud_in_port()
	await _test_chart()
	await _test_boat_care()
	await _test_hud_underway()
	await _test_fishing_and_adapter()
	SettingsManager.set_ui_light(SettingsManager.UI_LIGHT_AUTO)
	Simulation.auto_advance = true
	app.queue_free()
	await t.frames(2)
	GameSession.end_session()


func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)


func _set_local_hour(hour: float) -> void:
	var state := GameSession.get_state_snapshot()
	var geo := GameSession.get_vessel_position()
	var day_start := floorf(state.game_time / 86400.0) * 86400.0
	state.game_time = day_start + fposmod(hour - geo.x / 15.0, 24.0) * 3600.0
	GameSession.replace_state(state)


# --- Theme -------------------------------------------------------------------------------------

func _test_theme_foundation() -> void:
	var theme := ThemeDB.get_project_theme()
	t.check(theme != null and theme == UiTheme.theme, "[theme] the project theme is the one shared theme")
	var missing := PackedStringArray()
	for role: StringName in [&"surface", &"ink", &"heading", &"border", &"accent", &"focus", &"action", &"warning", &"caution",
			&"success", &"disabled_text", &"backdrop"]:
		if not UiTheme.PALETTES.has(role):
			missing.append(role)
	t.check(missing.is_empty(), "[theme] every semantic role has a day and a night colour%s" % ("" if missing.is_empty() else ": " + ", ".join(missing)))
	var variations := PackedStringArray()
	for type: StringName in [&"HudPanel", &"PromptPanel", &"WarningPanel", &"KeyBar", &"WarningLabel", &"SuccessLabel",
			&"MapButton", &"MenuItem", &"TocButton", &"BigButton"]:
		if not theme.has_stylebox(&"panel", type) and not theme.has_stylebox(&"normal", type) and not theme.has_color(&"font_color", type):
			variations.append(type)
	t.check(variations.is_empty(), "[theme] the screens' variations exist%s" % ("" if variations.is_empty() else ": " + ", ".join(variations)))
	var heading := theme.get_font(&"font", &"HeaderLabel") as FontVariation
	t.check(heading != null and heading.base_font.resource_path.contains("BarlowCondensed") and theme.default_font.resource_path.contains("Barlow"),
		"[type] headings are instrument lettering (Barlow Condensed); body text stays Barlow")
	# Contrast: body text on the panel surface, both moods (WCAG-style ratio).
	var ratios := []
	for night in [0.0, 1.0]:
		ratios.append(_contrast(UiTheme.color_at(&"ink", night), UiTheme.color_at(&"surface", night)))
		ratios.append(_contrast(UiTheme.color_at(&"button_text", night), UiTheme.color_at(&"button", night)))
		ratios.append(_contrast(UiTheme.color_at(&"action_text", night), UiTheme.color_at(&"action", night)))
	t.check(ratios.all(func(r: float) -> bool: return r >= 4.5), "[contrast] text on panels and buttons is at least 4.5:1 by day and night (%s)" %
		", ".join(ratios.map(func(r: float) -> String: return "%.1f" % r)))


static func _luminance(c: Color) -> float:
	var parts := [c.r, c.g, c.b].map(func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4))
	return 0.2126 * parts[0] + 0.7152 * parts[1] + 0.0722 * parts[2]


static func _contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _button_fill() -> Color:
	return (UiTheme.theme.get_stylebox(&"normal", &"Button") as StyleBoxFlat).bg_color


func _test_modes_and_settings() -> void:
	SettingsManager.set_ui_light(SettingsManager.UI_LIGHT_NIGHT)
	await t.frames(1)
	t.check(UiTheme.is_night() and _button_fill().is_equal_approx(UiTheme.color_at(&"button", 1.0)), "[mode] Always night: night mode")
	SettingsManager.set_ui_light(SettingsManager.UI_LIGHT_DAY)
	await t.frames(1)
	t.check(not UiTheme.is_night() and _button_fill().is_equal_approx(UiTheme.color_at(&"button", 0.0)), "[mode] Always day: sunlit display")
	# Stored in the settings file, not in the save.
	SettingsManager.set_ui_light(SettingsManager.UI_LIGHT_NIGHT)
	SettingsManager.save()
	SettingsManager.set_ui_light(SettingsManager.UI_LIGHT_AUTO)
	SettingsManager.load_settings()
	t.check_eq(SettingsManager.get_ui_light(), SettingsManager.UI_LIGHT_NIGHT, "[settings] the interface light is saved and loaded with the settings")
	var config := ConfigFile.new()
	config.load(SettingsManager.settings_path)
	t.check_eq(config.get_value("interface", "ui_light", ""), String(SettingsManager.UI_LIGHT_NIGHT), "[settings] in settings.cfg [interface]")
	GameSession.start_new_session()
	t.check(not JSON.stringify(GameSession.get_state_snapshot().to_dict()).contains("ui_light"), "[settings] and never in the save")
	GameSession.end_session()
	SettingsManager.set_ui_light(SettingsManager.UI_LIGHT_AUTO)
	SettingsManager.save()


func _test_automatic_follows_daylight() -> void:
	SettingsManager.set_ui_light(SettingsManager.UI_LIGHT_AUTO)
	_set_local_hour(12.5)
	UiTheme.set_blend(UiTheme._target_blend(), true)
	t.check(UiTheme.blend < 0.01, "[auto] local noon at the boat: day (%.2f)" % UiTheme.blend)
	_set_local_hour(23.5)
	t.check(UiTheme._target_blend() > 0.99, "[auto] local midnight: night is the target")
	await t.get_tree().create_timer(0.6).timeout
	t.check(UiTheme.blend > 0.0 and UiTheme.blend < 0.5, "[auto] the change eases in, not at once (%.2f after 0.6 s)" % UiTheme.blend)
	await t.wait_until(func() -> bool: return UiTheme.blend > 0.99, 15.0)
	t.check(UiTheme.blend > 0.99, "[auto] and arrives at Harbor Dusk within a few seconds (%.2f, target %.2f)" % [UiTheme.blend, UiTheme._target_blend()])
	var last := UiTheme.blend
	var changes := [0]
	var watcher := func() -> void: changes[0] += 1
	UiTheme.palette_changed.connect(watcher)
	await t.get_tree().create_timer(1.0).timeout
	UiTheme.palette_changed.disconnect(watcher)
	t.check(changes[0] == 0 and UiTheme.blend == last, "[auto] steady at night: no restyling while nothing changes (no per-frame rebuilds)")


func _test_open_window_survives() -> void:
	app.open_settings()
	await t.frames(3)
	var settings := app.modals.get_top() as ModalPanel
	var scrolls := settings.find_children("*", "ScrollContainer", true, false)
	if not scrolls.is_empty():
		(scrolls[0] as ScrollContainer).scroll_vertical = 40
	var before := (scrolls[0] as ScrollContainer).scroll_vertical if not scrolls.is_empty() else 0
	_set_local_hour(12.5)
	await t.wait_until(func() -> bool: return UiTheme.blend < 0.01, 8.0)
	t.check(app.modals.get_top() == settings and settings.is_visible_in_tree(), "[transition] dawn while Settings is open: it stays open")
	t.check(scrolls.is_empty() or (scrolls[0] as ScrollContainer).scroll_vertical == before, "[transition] and keeps its scroll position")
	app.modals.clear()
	await t.frames(2)


func _test_hud_in_port() -> void:
	app.modals.clear()
	GameSession.enter_boat_area(SessionState.AREA_EXTERIOR, &"start")
	app._show_current_boat_area()
	await _settle()
	var hud: Hud = app.hud
	hud.refresh()
	await t.frames(2)
	var route := hud.get_node("RoutePanel") as Control
	t.check(not (hud.find_child("RouteLabel", true, false) as Control).visible and (hud.find_child("WindLabel", true, false) as Control).visible
		and (hud.find_child("MenuButton", true, false) as Control).is_visible_in_tree() and route.size.x < Hud.ROUTE_PANEL_WIDTH,
		"[hud] no course planned: no empty route panel, just the wind and Menu (%d px wide)" % roundi(route.size.x))
	t.check((hud.get_node("Controls") as Control).theme_type_variation == &"KeyBar" and hud.get_controls_text().contains("E interact"),
		"[hud] the shortcuts stay, on a slim themed bar")
	hud.show_warning("Gale expected along your course.")
	await t.frames(2)
	var warning := hud.find_child("WarningPanel", true, false) as PanelContainer
	t.check(warning.is_visible_in_tree() and warning.theme_type_variation == &"WarningPanel", "[hud] warnings are never hidden, in their own warning panel")
	hud.hide_warning()


func _test_hud_underway() -> void:
	var hud: Hud = app.hud
	var route := hud.get_node("RoutePanel") as Control
	GameSession.plan_route_to(&"kiel")
	hud.refresh()
	await t.frames(2)
	t.check((hud.find_child("RouteLabel", true, false) as Control).visible and route.size.x >= Hud.ROUTE_PANEL_WIDTH - 1.0,
		"[hud] with a course: the route panel shows it")
	GameSession.depart()
	Simulation.advance(600.0)
	await t.frames(3)
	t.check(hud.sailing_panel.visible and not (hud.find_child("WindLabel", true, false) as Control).visible
		and not (hud.find_child("PropulsionLabel", true, false) as Control).visible and (hud.find_child("RouteLabel", true, false) as Control).visible,
		"[hud] underway: speed, sails and wind on the sailing panel only; the route panel keeps to the voyage")
	t.check(hud.get_route_text().contains("Kiel"), "[hud] %s" % hud.get_route_text())


func _test_chart() -> void:
	app.open_chart()
	await _settle()
	var map := app.router.current_screen as WorldMap
	if not t.check(map != null, "(setup) the chart is open"):
		return
	var small := true
	for name in ["ZoomInButton", "ZoomOutButton", "ResetViewButton", "CenterBoatButton"]:
		small = small and (map.find_child(name, true, false) as Control).theme_type_variation == &"MapButton"
	t.check(small and (map.find_child("WindToggle", true, false) as Control).theme_type_variation == &"MapToggle", "[chart] small map controls")
	map.select_port(&"gothenburg")
	await t.frames(3)
	var details := map.find_child("SelectionDetails", true, false) as Label
	t.check(not details.text.contains("(") and details.tooltip_text.contains("(") and details.tooltip_text.contains("°"),
		"[chart] a compact destination summary; the full services and position in its tooltip")
	map.plot_course_to(&"gothenburg")
	await t.frames(3)
	var apply := map.find_child("ApplyButton", true, false) as Button
	t.check(not apply.disabled and apply.is_visible_in_tree(), "[chart] the new course can be applied (%s)" % map.get_course_status_text().replace("\n", " / "))
	map.apply_course()
	await t.frames(3)
	t.check(GameSession.get_planned_route() != null and GameSession.get_planned_route().destination_port_id == &"gothenburg",
		"[chart] and is (the planned course is set)")
	var buttons := ["RemoveWaypointButton", "AnchorageButton", "ClearButton"]
	var clipped := PackedStringArray()
	for name in buttons:
		var button := map.find_child(name, true, false) as Button
		var font := button.get_theme_font(&"font")
		var width := font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size(&"font_size")).x
		if width > button.size.x - 20.0:
			clipped.append(button.text)
	t.check(clipped.is_empty(), "[chart] the waypoint buttons' labels fit (no '…')%s" % ("" if clipped.is_empty() else ": " + ", ".join(clipped)))
	app.close_chart()
	await _settle()


func _test_boat_care() -> void:
	app.open_boat_care()
	await t.frames(4)
	var care: ModalPanel = app.modals.get_top()
	t.check(care is BoatCareMenu and care.is_visible_in_tree(), "[cabin] boat care opens in the shared materials")
	app.modals.clear()
	await t.frames(2)


func _test_fishing_and_adapter() -> void:
	app.modals.clear()
	GameSession.enter_boat_area(SessionState.AREA_EXTERIOR, &"start")
	app._show_current_boat_area()
	await _settle()
	var catalog := FishingCatalog.get_default()
	GameSession.expire_bite()
	GameSession._pending_bite = {"species": "cod", "kg": 3.0, "time": GameSession.get_game_time(), "mode": "trolling",
		"lure": "spinner", "kind": String(catalog.kind_of("cod")), "rarity": catalog.rarity_of("cod")}
	var fishing: FishingMenu = app.open_fishing()
	await t.frames(6)
	if not t.check(fishing != null, "(setup) the fishing window opens"):
		return
	var dial := fishing.find_child("Dial", true, false) as ReelDial
	var dial_rect := dial.get_global_rect() if dial else Rect2()
	var covered := false
	for control: Control in fishing.find_children("*", "Control", true, false):
		if control == dial or not control.is_visible_in_tree() or dial.is_ancestor_of(control) or control.is_ancestor_of(dial):
			continue
		if (control is Label or control is Button) and control.get_global_rect().intersects(dial_rect.grow(-4.0)):
			covered = true
	t.check(dial != null and dial.is_visible_in_tree() and fishing.is_reeling() and not covered,
		"[fishing] the timing dial is shown and nothing sits over it")
	app.modals.clear()
	GameSession.expire_bite()
	await t.frames(2)
	# The tint adapter keeps a meaning colour right through the change of mood.
	var label := Label.new()
	app.add_child(label)
	UiTheme.tint(label, &"warning")
	UiTheme.set_blend(0.0, true)
	var day := label.get_theme_color(&"font_color")
	UiTheme.set_blend(1.0, true)
	var night := label.get_theme_color(&"font_color")
	t.check(day.is_equal_approx(UiTheme.color_at(&"warning", 0.0)) and night.is_equal_approx(UiTheme.color_at(&"warning", 1.0)),
		"[adapter] a warning tint follows the mood")
	UiTheme.tint(label, &"")
	t.check(not label.has_theme_color_override(&"font_color"), "[adapter] and can be taken off")
	label.queue_free()
	UiTheme.set_blend(UiTheme._target_blend(), true)
