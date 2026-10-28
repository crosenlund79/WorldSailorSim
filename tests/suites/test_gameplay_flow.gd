extends RefCounted
## End-to-end flow through the real application scene: main menu, new game,
## movement and collision, interactions, area transitions, the chart, pause
## menu, settings, save/load and returning to the main menu. Input is fed
## through the engine's input pipeline (key actions and mouse clicks).

const APP_SCENE := preload("res://src/app/app.tscn")

var t: Node
var app: Node


func run(runner: Node) -> void:
	t = runner
	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()

	await _test_main_menu()
	await _test_new_game_and_movement()
	await _test_interactions_in_cabin()
	await _test_chart()
	await _test_companionway_transitions()
	await _test_pause_and_settings()
	await _test_save_and_load()
	await _test_main_menu_return_and_continue()
	await _test_first_voyage_acceptance()
	WeatherFixtures.clear()
	await _test_quit()


# --- Steps -----------------------------------------------------------------------

func _test_main_menu() -> void:
	t.check(app.router.current_screen is MainMenu, "app starts on the main menu")
	var menu: MainMenu = app.router.current_screen
	var logo := menu.find_child("Logo", true, false) as TextureRect
	t.check(logo != null and logo.texture != null and logo.is_visible_in_tree(), "logo is displayed on the main menu")
	t.check(_button(menu, "ContinueButton").disabled, "Continue is disabled without a valid save")
	t.check(not _button(menu, "NewGameButton").disabled, "New Game is enabled")
	await t.screenshot("01_main_menu")

	# Settings from the main menu returns to the main menu.
	await t.click(_button(menu, "SettingsButton"))
	t.check(app.modals.get_top() is SettingsMenu, "Settings opens from the main menu")
	await t.screenshot("02_settings")
	await t.press_action(&"pause")
	t.check(app.modals.is_empty(), "Esc closes settings back to the main menu")

	# Load Game is disabled while every slot is empty.
	t.check(_button(menu, "LoadButton").disabled, "Load Game is disabled while all slots are empty")


func _test_new_game_and_movement() -> void:
	var menu: MainMenu = app.router.current_screen
	await t.click(_button(menu, "NewGameButton"))
	t.check(app.modals.get_top() is NewGameMenu, "New Game asks for the ship's companion")
	await t.click(_button(app.modals.get_top(), "StartButton"))
	await _settle()
	var area := app.router.current_screen as BoatArea
	t.check(area != null and area.area_id == &"interior", "New Game starts inside the boat (cabin)")
	t.check(GameSession.is_active(), "a session is active")
	t.check_eq(_player_count(), 1, "exactly one player exists")
	t.check(app.hud.is_visible_in_tree(), "HUD is visible in the boat")
	t.check_eq((app.hud.find_child("AreaLabel", true, false) as Label).text, "Cabin", "HUD shows the current area")
	var spawn: Vector2 = area.get_node("Layout/SpawnPoints/start").position
	t.check(area.player.position.distance_to(spawn) < 1.0, "player starts at the start spawn point")
	await t.screenshot("03_cabin")
	t.check_eq(GameSession.get_vessel_id(), &"arctic_wanderer_26", "New Game starts aboard the Arctic Wanderer 26")
	# The walks below were written for the Wing 33's cabin (the starter until 0.100b).
	await t.board(&"starling_33", app)
	area = app.router.current_screen as BoatArea

	var player := area.player
	var start := player.position
	await t.hold_actions([&"move_left"], 0.3)
	t.check(player.position.x < start.x - 40.0, "A/left moves the player left")
	start = player.position
	await t.hold_actions([&"move_right"], 0.3)
	t.check(player.position.x > start.x + 40.0, "D/right moves the player right")

	# Diagonal speed equals straight speed.
	Input.action_press(&"move_right")
	Input.action_press(&"move_down")
	await t.physics_frames(3)
	var diagonal_speed := player.velocity.length()
	Input.action_release(&"move_right")
	Input.action_release(&"move_down")
	await t.physics_frames(2)
	t.check(absf(diagonal_speed - player.speed) < 0.5, "diagonal movement is normalized (%.1f vs %.1f)" % [diagonal_speed, player.speed])

	# Walls and furniture stop the player.
	player.position = Vector2(-120, 0)
	await t.physics_frames(2)
	await t.hold_actions([&"move_up"], 1.2)
	t.check(player.position.y > -110.0, "settee blocks the player (y = %.1f)" % player.position.y)
	player.position = Vector2(-195, 0)
	await t.physics_frames(2)
	await t.hold_actions([&"move_left"], 1.0)
	t.check(player.position.x > -260.0, "companionway steps block the player (x = %.1f)" % player.position.x)
	player.position = Vector2(270, 0)
	await t.physics_frames(2)
	await t.hold_actions([&"move_right", &"move_up"], 1.5)
	t.check(player.position.y > -110.0 and player.position.x < 330.0, "hull and berth contain the player")
	t.check(Rect2(-330, -170, 790, 340).has_point(player.position), "player stays inside the cabin")


func _test_interactions_in_cabin() -> void:
	var area := app.router.current_screen as BoatArea
	var player := area.player
	await _move_player_to(Vector2(-110, 0))
	t.check_eq(app.hud.get_prompt(), "", "no prompt when nothing is in reach")

	await _move_player_to(Vector2(276, 0))
	t.check_eq(app.hud.get_prompt(), "Sleep", "prompt appears near the berth")
	await t.screenshot("04_prompt_berth")
	await t.press_action(&"interact")
	t.check(app.modals.get_top() is SleepMenu, "the berth opens the sleep menu")
	t.check(t.get_tree().paused, "the game pauses while choosing how long to sleep")
	await t.press_action(&"pause")
	t.check(app.modals.is_empty() and not t.get_tree().paused, "Esc closes the sleep menu without sleeping")

	# Between the companionway and the chart table both are in reach; the
	# closer one must win, and the choice must not flicker.
	var sensor: InteractionSensor = player.get_node("InteractionSensor")
	await _move_player_to(Vector2(-220, 40))
	var in_reach := sensor.get_overlapping_areas().filter(func(a: Area2D) -> bool: return a is Interactable)
	t.check_eq(in_reach.size(), 2, "two interactables are in reach between companionway and chart table")
	t.check_eq(sensor.focused.interaction_id, &"nav_table", "the closer chart table is focused")
	await t.physics_frames(5)
	t.check_eq(sensor.focused.interaction_id, &"nav_table", "focus stays stable while standing still")
	await _move_player_to(Vector2(-222, 8))
	t.check_eq(sensor.focused.interaction_id, &"companionway", "moving closer to the companionway switches focus")

	await _move_player_to(Vector2(-232, 62))
	t.check_eq(app.hud.get_prompt(), "Open chart", "prompt appears at the navigation table")
	GameSession.mark_saved()


func _test_chart() -> void:
	var position_at_table: Vector2 = (app.router.current_screen as BoatArea).player.position
	await t.press_action(&"interact")
	await _settle()
	var map := app.router.current_screen as WorldMap
	t.check(map != null, "navigation table opens the chart")
	if map == null:
		return
	# Since the I003b UI hotfix only the shared clock bar (time and Pause/1×/5×/20×) is shown on the chart.
	t.check(app.hud.is_chart_mode() and not app.hud.get_node("RoutePanel").visible and not app.hud.get_node("AreaPanel").visible
		and app.hud.get_node("ClockPanel").is_visible_in_tree(), "on the chart only the HUD's clock bar is shown")
	t.check_eq(_player_count(), 0, "no player exists while the chart is open")
	var view := map.get_map_view()
	await t.screenshot("05_chart")

	var zoom := view.get_zoom()
	view.zoom_by(1.5)
	t.check(view.get_zoom() > zoom * 1.4, "zoom in works")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = Vector2(700, 500)
	t.get_viewport().push_input(wheel, true)
	await t.frames(1)
	t.check(view.get_zoom() < zoom * 1.5, "mouse wheel zooms out")

	var camera_before := view.camera.position
	await _drag(Vector2(600, 500), Vector2(450, 420))
	t.check(view.camera.position.distance_to(camera_before) > 20.0, "dragging pans the chart")
	camera_before = view.camera.position
	await t.hold_actions([&"move_right"], 0.2)
	t.check(view.camera.position.x > camera_before.x, "keyboard pans the chart")
	view.reset_view()
	await t.frames(2)

	# Select Kiel by clicking its marker, then plot a course.
	view.center_on_geo(Vector2(11.4, 55.0), 0.6)
	await t.frames(2)
	await t.click_at(view.get_port_screen_position(&"kiel"))
	t.check_eq(map.get_selected_port_id(), &"kiel", "clicking a port selects it")
	var plot := map.find_child("PlotButton", true, false) as Button
	t.check(not plot.disabled, "Plot course is available for Kiel")
	await t.click(plot)
	t.check(map.get_draft_route() != null, "an automatic sea route to Kiel is calculated")
	t.check(GameSession.get_planned_route() == null, "the course is only a proposal until it is applied")
	await t.click(map.find_child("ApplyButton", true, false))
	var route := GameSession.get_planned_route()
	t.check(route != null and route.origin_port_id == &"copenhagen" and route.destination_port_id == &"kiel",
		"applying makes Copenhagen -> Kiel the planned course")
	t.check(route != null and route.path.size() > 2 and SeaRouter.get_default().validate_route(route).is_empty(),
		"the planned course is a validated multi-segment sea route")
	t.check(view.draft_legs.size() == 1 and view.draft_legs[0].path == route.path, "the chart draws exactly the planned course")
	await t.screenshot("06_chart_route")

	await t.click_at(view.get_port_screen_position(&"copenhagen"))
	t.check(plot.disabled, "cannot plot a course to the current port")
	var clear := map.find_child("ClearButton", true, false) as Button
	await t.click(clear)
	t.check(GameSession.get_planned_route() == null, "route can be cleared")
	t.check(clear.disabled, "Clear course is disabled without a route")
	await t.click_at(view.get_port_screen_position(&"kiel"))
	await t.click(plot)
	await t.click(map.find_child("ApplyButton", true, false))
	t.check(GameSession.get_planned_route() != null, "route can be plotted again")
	await _test_waypoint_editing(map)

	await t.press_action(&"pause")
	await _settle()
	var area := app.router.current_screen as BoatArea
	t.check(area != null and area.area_id == &"interior", "Esc returns from the chart to the cabin")
	if area:
		t.check(area.player.position.distance_to(position_at_table) < 1.0, "player is back at the navigation table")
	t.check(app.modals.is_empty() and not t.get_tree().paused, "closing the chart does not open the pause menu")
	t.check_eq((app.hud.find_child("RouteLabel", true, false) as Label).text,
		PlannedRoute.describe(GameSession.get_planned_route(), PortCatalog.get_default()), "HUD shows the planned route")


## Waypoint editing on the chart with the mouse; invalid edits never replace
## the committed course.
func _test_waypoint_editing(map: WorldMap) -> void:
	var view := map.get_map_view()
	var committed := GameSession.get_planned_route()
	var path := committed.path
	view.center_on_geo(Vector2(12.3, 55.1), 1.2)
	await t.frames(2)
	await _drag(_course_press_point(view, path), view.geo_to_screen(Vector2(12.9, 54.9)))
	t.check_eq(map.get_draft_waypoints().size(), 1, "dragging the course adds a waypoint")
	t.check(map.get_draft_route() != null, "the course is recalculated through the new waypoint")
	await t.screenshot("06b_chart_waypoint_drag")

	# Drag the waypoint onto land (Møn): it moves to the nearest open water
	# (Cozy Polish; no blocked line is left on the chart) and says so.
	await _drag(view.geo_to_screen(map.get_draft_waypoints()[0]), view.geo_to_screen(Vector2(12.35, 54.97)))
	t.check(map.get_draft_waypoints().size() == 1 and SeaRouter.get_default().is_point_reachable(map.get_draft_waypoints()[0]),
		"a waypoint let go on land moves to the nearest open water")
	t.check("nearest open water" in (map.find_child("CourseStatus", true, false) as Label).text, "the panel says the waypoint was moved")
	t.check(map.get_draft_route() != null and not (map.find_child("ApplyButton", true, false) as Button).disabled,
		"the course stays valid and can be applied")
	t.check(view.invalid_waypoints.is_empty() and view.draft_legs.all(func(l: Dictionary) -> bool: return l.ok),
		"no waypoint or leg is left marked blocked")
	t.check(GameSession.get_planned_route().path == committed.path, "the committed course is untouched while editing")
	await t.screenshot("06c_chart_invalid_waypoint")

	# Drag it back to sea, then remove it with a right-click.
	await _drag(view.geo_to_screen(map.get_draft_waypoints()[0]), view.geo_to_screen(Vector2(12.9, 54.85)))
	t.check(map.get_draft_route() != null, "moving the waypoint back to sea makes the course valid again")
	await t.click_at(view.geo_to_screen(map.get_draft_waypoints()[0]), MOUSE_BUTTON_RIGHT)
	t.check(map.get_draft_waypoints().is_empty(), "right-clicking a waypoint removes it")

	# Leaving with unapplied changes asks first; discarding keeps the course.
	await t.press_action(&"pause")
	t.check(app.modals.get_top() is ConfirmDialog, "leaving the chart with unapplied changes asks first")
	await t.click(_button(app.modals.get_top(), "CancelButton"))
	t.check(app.router.current_screen == map and app.modals.is_empty(), "Keep editing stays on the chart")
	await t.click(map.find_child("DiscardButton", true, false))
	t.check(not map.has_unapplied_changes(), "Discard returns to the committed course")
	t.check(GameSession.get_planned_route().path == committed.path, "the committed course is unchanged after discarding")


## A point on the course to press for a drag: the middle of its longest leg
## on screen. (Iteration 14: the detailed Danish chart gives the course more,
## shorter legs, so fixed leg numbers no longer mean the same place.)
func _course_press_point(view: MapView, path: PackedVector2Array) -> Vector2:
	var screen := Rect2(Vector2.ZERO, view.get_viewport_rect().size).grow(-40.0)
	var best := Vector2.ZERO
	var best_px := -1.0
	for i in range(1, path.size()):
		var a := view.geo_to_screen(path[i - 1])
		var b := view.geo_to_screen(path[i])
		var middle := view.geo_to_screen(GeoMath.rhumb_interpolate(path[i - 1], path[i], 0.5))
		if screen.has_point(middle) and a.distance_to(b) > best_px:
			best_px = a.distance_to(b)
			best = middle
	return best


func _test_companionway_transitions() -> void:
	await _move_player_to(Vector2(-222, 0))
	t.check_eq(app.hud.get_prompt(), "Go on deck", "companionway prompt in the cabin")
	await t.press_action(&"interact")
	await _settle()
	var deck := app.router.current_screen as BoatArea
	t.check(deck != null and deck.area_id == &"exterior", "companionway leads on deck")
	if deck == null:
		return
	t.check_eq(GameSession.get_boat_area(), &"exterior", "session records the deck as current area")
	var spawn: Vector2 = deck.get_node("Layout/SpawnPoints/from_cabin").position
	t.check(deck.player.position.distance_to(spawn) < 1.0, "player arrives at the companionway on deck")
	t.check_eq((app.hud.find_child("AreaLabel", true, false) as Label).text, "Deck", "HUD shows Deck")
	await t.screenshot("07_deck")

	await _move_player_to(Vector2(-448, 0))
	t.check_eq(app.hud.get_prompt(), "Take the helm", "helm prompt")
	await t.press_action(&"interact")
	t.check(app.modals.get_top() is ConfirmDialog, "with a planned course the helm offers to set sail")
	await t.click(_button(app.modals.get_top(), "CancelButton"))
	t.check(not GameSession.is_underway(), "cancelling at the helm keeps the boat moored")

	# Deck boundaries hold.
	await _move_player_to(Vector2(0, -130))
	await t.hold_actions([&"move_up"], 1.0)
	t.check(deck.player.position.y > -170.0, "lifelines keep the player on deck")
	await _move_player_to(Vector2(300, 0))
	await t.hold_actions([&"move_right"], 1.5)
	t.check(deck.player.position.x < 495.0, "bow pulpit stops the player")

	# Repeated round trips never duplicate the player or the screen.
	var trail: Array[String] = []
	for i in 3:
		await _to_hatch(Vector2(-262, 0), "Go below")
		trail.append("%s:%s" % [GameSession.get_boat_area(), app.hud.get_prompt()])
		await t.press_action(&"interact")
		await _settle()
		await _to_hatch(Vector2(-222, 0), "Go on deck")
		trail.append("%s:%s" % [GameSession.get_boat_area(), app.hud.get_prompt()])
		await t.press_action(&"interact")
		await _settle()
	t.check_eq(_player_count(), 1, "repeated transitions keep exactly one player")
	t.check_eq(app.get_node("Screen").get_child_count(), 1, "only one screen is loaded")
	t.check_eq(GameSession.get_boat_area(), &"exterior", "ended on deck after round trips (area:prompt before each E: %s; modals %d, companion %s)" % [
		trail, app.modals.depth(), GameSession.get_companion().area])


## Walks to the companionway at `spot`. The ship's companion wanders and
## sometimes sits right there, and E would pet it instead of using the hatch
## (the intermittent "ended on deck" failure): it is moved aside first.
func _to_hatch(spot: Vector2, prompt: String) -> void:
	await _move_player_to(spot)
	if app.hud.get_prompt() != prompt:
		var companion := app.router.current_screen.get_node_or_null(^"Companion") as Node2D
		if companion:
			companion.position = spot + Vector2(400, 0)
		await t.physics_frames(3)
		await _move_player_to(spot)


func _test_pause_and_settings() -> void:
	var area := app.router.current_screen as BoatArea
	await t.press_action(&"pause")
	t.check(app.modals.get_top() is PauseMenu, "Esc opens the pause menu")
	t.check(t.get_tree().paused, "gameplay is paused")
	await t.screenshot("08_pause")
	var before := area.player.position
	await t.hold_actions([&"move_right"], 0.3)
	t.check(area.player.position.is_equal_approx(before), "player cannot move while paused")

	var pause: PauseMenu = app.modals.get_top()

	# UI scale enlarges menus and HUD while their layout still fits the screen.
	SettingsManager.set_ui_scale(1.3)
	await t.frames(3)
	var layer := app.get_node("ModalLayer") as CanvasLayer
	t.check(layer.scale.is_equal_approx(Vector2(1.3, 1.3)), "UI scale is applied to the menu layer")
	var stack_size: Vector2 = (layer.get_node("ModalStack") as Control).size
	t.check(stack_size.is_equal_approx(t.get_viewport().get_visible_rect().size / 1.3), "scaled UI still covers the screen exactly")
	var resume_rect := _button(pause, "ResumeButton").get_global_rect()
	t.check(Rect2(Vector2.ZERO, stack_size).encloses(resume_rect), "scaled pause menu stays on screen")
	await t.screenshot("08b_pause_ui_scale_130")
	SettingsManager.set_ui_scale(1.0)
	await t.frames(2)

	await t.click(_button(pause, "SettingsButton"))
	t.check(app.modals.get_top() is SettingsMenu, "Settings opens from the pause menu")
	t.check(not pause.visible, "pause menu is hidden behind settings")
	var settings: SettingsMenu = app.modals.get_top()

	# Changing a slider applies immediately; leaving asks to discard.
	var music_slider: HSlider = settings._volume_sliders[&"Music"]
	music_slider.value = 30
	t.check_eq(SettingsManager.get_volume(&"Music"), 30, "music slider changes the setting immediately")
	t.check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music")) - linear_to_db(0.3)) < 0.01,
		"music slider changes the Music bus volume")
	music_slider.value = 0
	t.check(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Music")), "music slider at 0 mutes the bus")
	await t.press_action(&"pause")
	t.check(app.modals.get_top() is ConfirmDialog, "leaving with unapplied changes asks for confirmation")
	await t.screenshot("09_settings_confirm")
	await t.click(_button(app.modals.get_top(), "ConfirmButton"))
	t.check_eq(SettingsManager.get_volume(&"Music"), SettingsManager.DEFAULT_VOLUMES[&"Music"], "discarding restores the previous volume")
	t.check(app.modals.get_top() is PauseMenu and pause.visible, "settings return to the pause menu")

	# Apply persists; Restore Defaults resets.
	await t.click(_button(pause, "SettingsButton"))
	settings = app.modals.get_top()
	(settings._volume_sliders[&"SFX"] as HSlider).value = 40
	await t.click(_button(settings, "ApplyButton"))
	t.check(FileAccess.file_exists(t.TEST_SETTINGS_PATH), "Apply writes the settings file")
	var config := ConfigFile.new()
	config.load(t.TEST_SETTINGS_PATH)
	t.check_eq(config.get_value("audio", "sfx"), 40, "applied SFX volume is stored")
	await t.click(_button(settings, "DefaultsButton"))
	t.check_eq(SettingsManager.get_volume(&"SFX"), 80, "Restore Defaults resets the SFX volume")
	await t.click(_button(settings, "ApplyButton"))
	await t.click(_button(settings, "BackButton"))
	t.check(app.modals.get_top() is PauseMenu, "Back returns to the pause menu")

	await t.click(_button(pause, "ResumeButton"))
	t.check(app.modals.is_empty() and not t.get_tree().paused, "Resume closes the menu and unpauses")
	await t.hold_actions([&"move_right"], 0.2)
	t.check(not area.player.position.is_equal_approx(before), "player moves again after resuming")


func _test_save_and_load() -> void:
	var area := app.router.current_screen as BoatArea
	await _move_player_to(Vector2(-330, 30))
	var saved_state := GameSession.get_state_snapshot().to_dict()

	await _open_pause_and_click("SaveButton")
	var menu := app.modals.get_top() as SaveLoadMenu
	t.check(menu != null and menu.mode == SaveLoadMenu.Mode.SAVE, "Save Game opens the save dialog")
	await t.screenshot("10_save_dialog")
	await t.click(menu.find_child("Slot1", true, false))
	t.check(_toast_contains("Game saved to slot 1"), "saving reports success")
	t.check(app.modals.get_top() is PauseMenu, "save dialog closes back to the pause menu")
	t.check(not GameSession.has_unsaved_changes(), "session is marked as saved")
	t.check(SaveManager.get_slot_info(1).is_loadable(), "slot 1 contains a valid save")

	# Save to a second slot, then overwrite slot 1 with confirmation.
	await t.click(_button(app.modals.get_top(), "SaveButton"))
	await t.click(app.modals.get_top().find_child("Slot2", true, false))
	t.check(SaveManager.get_slot_info(2).is_loadable(), "slot 2 contains a valid save")
	await t.click(_button(app.modals.get_top(), "SaveButton"))
	await t.click(app.modals.get_top().find_child("Slot1", true, false))
	t.check(app.modals.get_top() is ConfirmDialog, "overwriting an occupied slot asks for confirmation")
	await t.click(_button(app.modals.get_top(), "CancelButton"))
	t.check(app.modals.get_top() is SaveLoadMenu, "cancelling an overwrite returns to the slot list")
	await t.click(app.modals.get_top().find_child("Slot1", true, false))
	await t.click(_button(app.modals.get_top(), "ConfirmButton"))
	t.check(app.modals.get_top() is PauseMenu, "confirmed overwrite saves and closes the dialog")
	await t.click(_button(app.modals.get_top(), "ResumeButton"))

	# Change the session: different area, position and no route.
	GameSession.clear_planned_route()
	await _move_player_to(Vector2(-262, 0))
	await t.press_action(&"interact")
	await _settle()
	await _move_player_to(Vector2(0, 0))
	t.check(GameSession.has_unsaved_changes(), "changes after saving are tracked")

	# Load slot 1: asks to discard progress, then restores everything.
	await _open_pause_and_click("LoadButton")
	var load_menu := app.modals.get_top() as SaveLoadMenu
	t.check(load_menu != null and load_menu.mode == SaveLoadMenu.Mode.LOAD, "Load Game opens the load dialog")
	var empty_slot := load_menu.find_child("Slot3", true, false) as Button
	t.check(empty_slot.disabled, "empty slots cannot be loaded")
	await t.screenshot("11_load_dialog")
	await t.click(load_menu.find_child("Slot1", true, false))
	t.check(app.modals.get_top() is ConfirmDialog, "loading with unsaved progress asks for confirmation")
	await t.click(_button(app.modals.get_top(), "ConfirmButton"))
	await _settle()
	area = app.router.current_screen as BoatArea
	t.check(area != null and area.area_id == &"exterior", "loading restores the saved area (deck)")
	t.check(_same_state(GameSession.get_state_snapshot().to_dict(), saved_state), "loading restores the saved session state")
	if area:
		t.check(area.player.position.distance_to(Vector2(saved_state.player.position.x, saved_state.player.position.y)) < 1.0,
			"loading restores the player position")
	t.check(GameSession.get_planned_route() != null and GameSession.get_planned_route().destination_port_id == &"kiel",
		"loading restores the planned route")
	t.check(app.modals.is_empty() and not t.get_tree().paused, "game resumes after loading")
	t.check_eq(_player_count(), 1, "loading does not duplicate the player")

	# A damaged slot is reported and leaves the session untouched.
	var damaged := FileAccess.open(SaveManager.save_dir.path_join("slot_3.json"), FileAccess.WRITE)
	damaged.store_string("{\"format\": \"next_harbor_save\", \"version\": 1, \"session\": 42}")
	damaged.close()
	Simulation.auto_advance = false  # freeze the clock for an exact comparison
	var state_before := GameSession.get_state_snapshot().to_dict()
	app.load_slot(3)
	await t.frames(2)
	t.check(_toast_contains("Could not load slot 3"), "loading a damaged save reports an error")
	t.check_eq(GameSession.get_state_snapshot().to_dict(), state_before, "a failed load leaves the session unchanged")
	t.check(app.router.current_screen == area, "a failed load keeps the current scene")
	Simulation.auto_advance = true


func _test_main_menu_return_and_continue() -> void:
	await _move_player_to(Vector2(-300, 0))
	await _open_pause_and_click("MainMenuButton")
	t.check(app.modals.get_top() is ConfirmDialog, "returning to the main menu with unsaved progress asks first")
	await t.click(_button(app.modals.get_top(), "CancelButton"))
	t.check(app.modals.get_top() is PauseMenu, "cancel keeps the game running behind the pause menu")
	await t.click(_button(app.modals.get_top(), "MainMenuButton"))
	await t.click(_button(app.modals.get_top(), "ConfirmButton"))
	await _settle()
	t.check(app.router.current_screen is MainMenu, "returns to the main menu")
	t.check(not GameSession.is_active(), "session ends on returning to the main menu")
	t.check(not t.get_tree().paused, "main menu is not paused")
	t.check_eq(_player_count(), 0, "no player remains after leaving the game")

	var menu: MainMenu = app.router.current_screen
	t.check(not _button(menu, "ContinueButton").disabled, "Continue is enabled once a valid save exists")
	t.check(not _button(menu, "LoadButton").disabled, "Load Game is enabled once a save exists")
	await t.click(_button(menu, "LoadButton"))
	t.check(app.modals.get_top() is SaveLoadMenu, "Load Game opens the slot list from the main menu")
	await t.press_action(&"pause")
	t.check(app.modals.is_empty(), "Esc closes the slot list")

	var newest := SaveManager.get_most_recent_valid_slot()
	var expected := SaveManager.load_from_slot(newest).state.to_dict()
	await t.click(_button(menu, "ContinueButton"))
	await _settle()
	t.check(app.router.current_screen is BoatArea, "Continue loads into the boat")
	t.check(_same_state(GameSession.get_state_snapshot().to_dict(), expected), "Continue loads the most recent save (slot %d)" % newest)

	await _open_pause_and_click("MainMenuButton")
	if app.modals.get_top() is ConfirmDialog:
		await t.click(_button(app.modals.get_top(), "ConfirmButton"))
	await _settle()

	# New Game must not touch existing save slots.
	var slot_files := {}
	for slot in [1, 2]:
		slot_files[slot] = FileAccess.get_file_as_string(SaveManager.save_dir.path_join("slot_%d.json" % slot))
	await t.click(_button(app.router.current_screen, "NewGameButton"))
	await t.click(_button(app.modals.get_top(), "StartButton"))
	await _settle()
	var untouched := true
	for slot: int in slot_files:
		untouched = untouched and FileAccess.get_file_as_string(SaveManager.save_dir.path_join("slot_%d.json" % slot)) == slot_files[slot]
	t.check(untouched, "New Game does not overwrite manual save slots")
	t.check(GameSession.get_planned_route() == null, "New Game starts without a route")
	app.show_main_menu()
	await _settle()


## The owner's acceptance scenario for Iteration 002, through the real UI.
func _test_first_voyage_acceptance() -> void:
	var catalog := PortCatalog.get_default()
	# 1-2. New game in Copenhagen.
	await t.click(_button(app.router.current_screen, "NewGameButton"))
	await t.click(_button(app.modals.get_top(), "StartButton"))
	await _settle()
	t.check_eq(GameSession.get_location_id(), &"copenhagen", "[voyage] a new game starts in Copenhagen")
	# The acceptance walk was written for the Wing 33 (the starter until 0.100b).
	await t.board(&"starling_33", app)

	# 3-4. Walk to the navigation station and open the European chart.
	await _move_player_to(Vector2(-232, 62))
	await t.press_action(&"interact")
	await _settle()
	var map := app.router.current_screen as WorldMap
	if not t.check(map != null, "[voyage] the chart table opens the European chart"):
		return
	var view := map.get_map_view()
	view.reset_view()
	await t.frames(2)
	var visible := Rect2(Vector2.ZERO, t.get_viewport().get_visible_rect().size)
	t.check(visible.has_point(view.get_port_screen_position(&"reykjavik")) and visible.has_point(view.get_port_screen_position(&"piraeus")),
		"[voyage] the whole-Europe view shows ports from Iceland to Greece (%s, %s)" % [
			view.get_port_screen_position(&"reykjavik"), view.get_port_screen_position(&"piraeus")])
	await t.screenshot("12_chart_europe")

	# 5-7. Select Kiel and plot an automatic sea route that avoids Zealand.
	view.center_on_geo(Vector2(11.6, 55.0), 0.7)
	await t.frames(2)
	await t.click_at(view.get_port_screen_position(&"kiel"))
	await t.click(map.find_child("PlotButton", true, false))
	var draft := map.get_draft_route()
	t.check(draft != null and SeaRouter.get_default().validate_route(draft).is_empty(), "[voyage] an automatic sea route to Kiel is plotted")
	var distance_before := draft.get_distance_nm() if draft else 0.0

	# 8-9. Drag the course line to add a waypoint; the distance updates.
	var target_geo := Vector2(12.78, 55.30)
	await _drag(_course_press_point(view, draft.path), view.geo_to_screen(target_geo))
	await t.frames(2)
	t.check_eq(map.get_draft_waypoints().size(), 1, "[voyage] dragging the course line adds a waypoint")
	draft = map.get_draft_route()
	t.check(draft != null and draft.waypoints.size() == 1, "[voyage] the course is recalculated through the waypoint")
	t.check(draft != null and not is_equal_approx(draft.get_distance_nm(), distance_before),
		"[voyage] the distance updates (%d -> %d nm)" % [roundi(distance_before), roundi(draft.get_distance_nm()) if draft else 0])
	t.check(str(roundi(draft.get_distance_nm())) in (map.find_child("CourseLabel", true, false) as Label).text if draft else false,
		"[voyage] the side panel shows the new distance")
	await t.screenshot("13_chart_waypoint")

	# 10. Confirm the route and return to the boat.
	await t.click(map.find_child("ApplyButton", true, false))
	t.check(GameSession.get_planned_route() != null and GameSession.get_planned_route().waypoints.size() == 1, "[voyage] the course with its waypoint is applied")
	await t.press_action(&"pause")
	await _settle()

	# 11. Depart at the helm.
	await _move_player_to(Vector2(-222, 0))
	await t.press_action(&"interact")
	await _settle()
	await _move_player_to(Vector2(-448, 0))
	await t.press_action(&"interact")
	t.check(app.modals.get_top() is ConfirmDialog, "[voyage] the helm asks to set sail")
	await t.click(_button(app.modals.get_top(), "ConfirmButton"))
	t.check(GameSession.is_underway(), "[voyage] the boat departs")
	var deck := app.router.current_screen as BoatArea
	t.check(deck != null and not deck.get_node("Surroundings/Mooring").visible, "[voyage] the pontoon is left behind on deck")

	# 12. The boat moves along the route.
	var progress := GameSession.get_voyage_progress_nm()
	await t.get_tree().create_timer(1.0).timeout
	t.check(GameSession.get_voyage_progress_nm() > progress, "[voyage] the boat moves along the route in real time")
	await t.screenshot("14_deck_underway")

	# 13-14. Inspect progress on the chart, then return to the cabin.
	await _move_player_to(Vector2(-262, 0))
	await t.press_action(&"interact")
	await _settle()
	await _move_player_to(Vector2(-232, 62))
	await t.press_action(&"interact")
	await _settle()
	map = app.router.current_screen as WorldMap
	if not t.check(map != null, "[voyage] the chart opens while underway"):
		return
	await t.frames(2)
	t.check(map.get_map_view().vessel_geo.distance_to(GameSession.get_vessel_position()) < 1e-3 and map.get_map_view().boat_port_id.is_empty(),
		"[voyage] the chart shows the vessel at its actual position at sea")
	await t.screenshot("15_chart_underway")
	await t.press_action(&"pause")
	await _settle()

	# 15-16. 20x time acceleration from the HUD.
	await t.click(app.hud.find_child("Speed20", true, false))
	t.check_eq(GameSession.get_time_scale(), 20, "[voyage] the HUD switches to 20×")
	var time_before := GameSession.get_game_time()
	await t.get_tree().create_timer(0.5).timeout
	var game_seconds := GameSession.get_game_time() - time_before
	t.check(game_seconds > 300.0, "[voyage] at 20× half a real second covers %d game seconds" % roundi(game_seconds))
	await t.click(app.hud.find_child("Speed1", true, false))

	# 17-19. Sleep at the berth.
	SettingsManager.set_sleep_hours(SettingsManager.DEFAULT_SLEEP_HOURS, false)  # the dialog remembers the last choice (Cozy Polish)
	await _move_player_to(Vector2(276, 0))
	await t.press_action(&"interact")
	var progress_before_sleep := GameSession.get_voyage_progress_nm()
	var sleep_menu := app.modals.get_top() as SleepMenu
	for i in 2:
		await t.click(sleep_menu.find_child("DecreaseButton", true, false))
	await t.click(sleep_menu.find_child("SleepButton", true, false))
	await _settle()
	t.check(app.modals.is_empty(), "[voyage] the sleep menu closes")
	t.check(absf(GameSession.get_voyage_progress_nm() - progress_before_sleep - 20.0) < 0.5,
		"[voyage] 4 h of sleep advance the voyage ~20 nm (%.1f nm)" % (GameSession.get_voyage_progress_nm() - progress_before_sleep))
	t.check(_toast_contains("You slept 4 h"), "[voyage] waking up reports the time")

	# 20-23. Save underway, leave to the main menu, load again.
	await _open_pause_and_click("SaveButton")
	await t.click(app.modals.get_top().find_child("Slot3", true, false))
	if app.modals.get_top() is ConfirmDialog:
		await t.click(_button(app.modals.get_top(), "ConfirmButton"))
	var saved := SaveManager.load_from_slot(3).state
	t.check(saved != null and saved.voyage != null, "[voyage] the game is saved while underway")
	await t.click(_button(app.modals.get_top(), "MainMenuButton"))
	if app.modals.get_top() is ConfirmDialog:
		await t.click(_button(app.modals.get_top(), "ConfirmButton"))
	await _settle()
	t.check(app.router.current_screen is MainMenu, "[voyage] back at the main menu")
	await t.click(_button(app.router.current_screen, "LoadButton"))
	await t.click(app.modals.get_top().find_child("Slot3", true, false))
	await _settle()
	t.check(GameSession.is_underway() and GameSession.get_voyage_destination_id() == &"kiel", "[voyage] the loaded game is underway to Kiel")
	if saved:
		t.check(absf(GameSession.get_voyage_progress_nm() - saved.voyage.progress_nm) < 0.5,
			"[voyage] the voyage resumes from the saved position, not from Copenhagen")

	# 24. A weather warning cuts the sleep short. A strong-wind area forms an
	# hour into the sleep on the Copenhagen -> Kiel course 40 nm ahead (a
	# fixture of the weather model, off Darss as in Iteration 002).
	var course := GameSession.get_voyage().route.path
	var area_center := GeoMath.point_along(course, GeoMath.cumulative_distances(course), GameSession.get_voyage_progress_nm() + 40.0)
	WeatherFixtures.use([WeatherFixtures.gale("test_strong_winds", area_center, 9.0, 26.0,
		GameSession.get_game_time() + 3600.0, 24.0 * 365.0)])
	app.sleep_for(8.0)
	await _settle()
	t.check(app.hud.is_warning_visible(), "[voyage] the strong-wind warning is shown in the HUD")
	t.check(_toast_contains("woken") and _toast_contains("Strong winds"), "[voyage] sleep was interrupted by the warning")
	var position_at_warning := GameSession.get_vessel_position()
	var time_at_warning := GameSession.get_game_time()
	await t.screenshot("16_weather_warning")

	# 25-26. Open the chart from the warning and steer around the area.
	await t.frames(2)  # let the newly shown warning panel lay out
	await t.click(app.hud.find_child("WarningChartButton", true, false))
	await _settle()
	map = app.router.current_screen as WorldMap
	if not t.check(map != null, "[voyage] the warning's View chart button opens the chart"):
		return
	await t.frames(2)
	t.check_eq(map.get_current_tab(), WorldMap.TAB_WEATHER, "[voyage] View chart opens the chart on its Weather tab")
	Simulation.auto_advance = false  # hold the boat still while editing for exact checks
	view = map.get_map_view()
	view.center_on_geo(Vector2(12.4, 54.9), 1.2)
	await t.frames(2)
	var leg: PackedVector2Array = map.get_draft_legs()[0].path
	var ahead := GeoMath.point_along(leg, GeoMath.cumulative_distances(leg), 6.0)
	await _drag(view.geo_to_screen(ahead), view.geo_to_screen(Vector2(12.62, 54.55)))
	await t.frames(2)
	var new_course := map.get_draft_route()
	t.check(new_course != null and new_course.origin_port_id.is_empty(), "[voyage] the new course starts at sea from the vessel")
	var avoids := new_course != null and Simulation.route_hazards(new_course.path, 0.0, 1000.0).is_empty()
	t.check(avoids, "[voyage] the adjusted course avoids the strong winds")
	await t.screenshot("17_chart_reroute")
	await t.click(map.find_child("ApplyButton", true, false))
	t.check_eq(GameSession.get_voyage().revision, 2, "[voyage] the course is changed at sea")
	# A few game seconds pass while the chart opens (the clock check below
	# allows 120 s), and the boat sails on in them: about 110 m, which was
	# right at the old fixed 1e-3° limit (intermittent). No teleport means no
	# more than it could sail in that time (12 kn) plus 10 m.
	var moved_m := GeoMath.distance_nm(position_at_warning, GameSession.get_vessel_position()) * 1852.0
	var could_m := (GameSession.get_game_time() - time_at_warning) * 12.0 * 1852.0 / 3600.0 + 10.0
	t.check(moved_m <= could_m, "[voyage] no teleport: the boat stays where it was (%.0f m in %.0f s of game time; at most %.0f m)" % [
		moved_m, GameSession.get_game_time() - time_at_warning, could_m])
	t.check(GameSession.get_game_time() - time_at_warning < 120.0, "[voyage] the clock is preserved")
	Simulation.auto_advance = true
	await t.press_action(&"pause")
	await _settle()

	# 27-30. Continue to Kiel without returning to Copenhagen.
	for i in 6:
		if not GameSession.is_underway():
			break
		app.sleep_for(8.0)
		await _settle()
	t.check_eq(GameSession.get_location_id(), &"kiel", "[voyage] the boat reaches Kiel")
	t.check(_toast_contains("Arrived in Kiel"), "[voyage] arrival is announced")
	t.check(GameSession.get_vessel_position().is_equal_approx(catalog.get_port(&"kiel").get_geo_position()), "[voyage] the vessel lies in Kiel")
	await t.frames(2)
	t.check_eq((app.hud.find_child("LocationLabel", true, false) as Label).text, "Arrived at Kiel", "[voyage] the HUD shows the new location")
	await t.screenshot("18_arrived_kiel")

	# 31. Plot the next voyage from Kiel.
	var area := app.router.current_screen as BoatArea
	if area.area_id == SessionState.AREA_EXTERIOR:
		await _move_player_to(Vector2(-262, 0))
		await t.press_action(&"interact")
		await _settle()
	await _move_player_to(Vector2(-232, 62))
	await t.press_action(&"interact")
	await _settle()
	map = app.router.current_screen as WorldMap
	if t.check(map != null, "[voyage] the chart opens in Kiel"):
		map.select_port(&"gothenburg")
		await t.click(map.find_child("PlotButton", true, false))
		var next := map.get_draft_route()
		t.check(next != null and next.origin_port_id == &"kiel", "[voyage] the next course is plotted from Kiel")
	app.show_main_menu()
	await _settle()


func _test_quit() -> void:
	# Quitting ends this test process, so it is the last step and only runs
	# when everything else passed (the exit code must reflect failures).
	if t.failed > 0:
		return
	var menu: MainMenu = app.router.current_screen
	t.check(menu != null, "main menu is shown before quitting")
	print("\n%d checks passed, 0 failed. Pressing Quit; the process should now exit with code 0." % t.passed)
	await t.click(_button(menu, "QuitButton"))
	await t.frames(30)
	t.check(false, "Quit should have closed the application")


## Equal session states, allowing the clock to have run on for a few seconds
## of real time since loading (the game clock keeps going while tests wait).
func _same_state(actual: Dictionary, expected: Dictionary) -> bool:
	var a: Dictionary = actual.duplicate(true)
	var b: Dictionary = expected.duplicate(true)
	var drift: float = a.clock.game_time - b.clock.game_time
	a.clock.erase("game_time")
	b.clock.erase("game_time")
	# Food and water are used up with the game time that passed since loading.
	var stores_ok := true
	for key in ["food_days", "water_days"]:
		var used: float = b.provisions[key] - a.provisions[key]
		stores_ok = stores_ok and absf(used - drift / Provisions.DAY_SECONDS) < 1e-6
		a.provisions.erase(key)
		b.provisions.erase(key)
	# The captain's hat is checked on the game clock (Visual Identity V01):
	# its checks follow the time that passed, like the stores.
	if a.has("hat") and b.has("hat"):
		var checked: float = a.hat.checked_until - b.hat.checked_until
		stores_ok = stores_ok and checked >= 0.0 and checked <= drift + HatConfig.get_default().check_interval_s
		a.hat.erase("checked_until")
		b.hat.erase("checked_until")
	return _same(a, b) and stores_ok and drift >= 0.0 and drift < 20.0 * Simulation.game_seconds_per_real_second


## Equal values, numbers to 1e-9 relative. Iteration 17: Godot's JSON parser
## does not always give back the last bit of a double written at full
## precision, which made the exact comparison fail in about one run in four
## (seen on the Iteration 16 build too); nothing a player could notice.
func _same(a: Variant, b: Variant) -> bool:
	if (typeof(a) == TYPE_FLOAT or typeof(a) == TYPE_INT) and (typeof(b) == TYPE_FLOAT or typeof(b) == TYPE_INT):
		return absf(float(a) - float(b)) <= 1e-9 * maxf(1.0, absf(float(a)))
	if typeof(a) != typeof(b):
		return false
	if a is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not _same(a[k], b[k]):
				return false
		return true
	if a is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _same(a[i], b[i]):
				return false
		return true
	return a == b


# --- Helpers -------------------------------------------------------------------------

func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)


func _move_player_to(position: Vector2) -> void:
	var area := app.router.current_screen as BoatArea
	area.player.position = position
	await t.physics_frames(3)


func _drag(from: Vector2, to: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from
	t.get_viewport().push_input(press, true)
	var steps := 5
	var previous := from
	for i in range(1, steps + 1):
		var motion := InputEventMouseMotion.new()
		motion.position = from.lerp(to, float(i) / steps)
		motion.relative = motion.position - previous
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		previous = motion.position
		t.get_viewport().push_input(motion, true)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = to
	t.get_viewport().push_input(release, true)
	await t.frames(2)


func _open_pause_and_click(button_name: String) -> void:
	if not app.modals.get_top() is PauseMenu:
		await t.press_action(&"pause")
	await t.click(_button(app.modals.get_top(), button_name))


func _button(root: Node, button_name: String) -> Button:
	return root.find_child(button_name, true, false) as Button


func _player_count() -> int:
	return t.get_tree().get_nodes_in_group(&"player").size()


func _toast_contains(text: String) -> bool:
	for message in app.toasts.get_messages():
		if text in message:
			return true
	return false
