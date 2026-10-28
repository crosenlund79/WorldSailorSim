extends Node
## Minimal self-contained test runner (no external framework).
##
## Run headless:
##   godot --headless --path . res://tests/test_runner.tscn
## Run with rendering and save screenshots (e.g. under Xvfb):
##   godot --path . res://tests/test_runner.tscn -- --screenshots=/some/dir
##
## Tests use scratch files (user://test_saves, user://test_settings.cfg) so the
## player's real saves and settings are never touched. The exit code is 0
## only if every check passed.

const SUITES: Array[Script] = [
	preload("res://tests/suites/test_data_model.gd"),
	preload("res://tests/suites/test_routing.gd"),
	preload("res://tests/suites/test_world_chart_render.gd"),
	preload("res://tests/suites/test_route_wrap.gd"),
	preload("res://tests/suites/test_wind_overlay.gd"),
	preload("res://tests/suites/test_sailing_correctness.gd"),
	preload("res://tests/suites/test_navigation_views.gd"),
	preload("res://tests/suites/test_cockpit_ui.gd"),
	preload("res://tests/suites/test_lighting.gd"),
	preload("res://tests/suites/test_atmosphere.gd"),
	preload("res://tests/suites/test_presentation.gd"),
	preload("res://tests/suites/test_regions.gd"),
	preload("res://tests/suites/test_boat_care.gd"),
	preload("res://tests/suites/test_denmark_views.gd"),
	preload("res://tests/suites/test_anchor_life.gd"),
	preload("res://tests/suites/test_simulation.gd"),
	preload("res://tests/suites/test_wind.gd"),
	preload("res://tests/suites/test_sailing.gd"),
	preload("res://tests/suites/test_reassessment.gd"),
	preload("res://tests/suites/test_save_manager.gd"),
	preload("res://tests/suites/test_voyage_persistence.gd"),
	preload("res://tests/suites/test_settings_and_audio.gd"),
	preload("res://tests/suites/test_sailing_presentation.gd"),
	preload("res://tests/suites/test_life_aboard.gd"),
	preload("res://tests/suites/test_chart_and_pause.gd"),
	preload("res://tests/suites/test_vessels.gd"),
	preload("res://tests/suites/test_catamaran_cabin.gd"),
	preload("res://tests/suites/test_companion_art.gd"),
	preload("res://tests/suites/test_dev_guides.gd"),
	preload("res://tests/suites/test_weather.gd"),
	preload("res://tests/suites/test_weather_ui.gd"),
	preload("res://tests/suites/test_upkeep.gd"),
	preload("res://tests/suites/test_upkeep_ui.gd"),
	preload("res://tests/suites/test_living.gd"),
	preload("res://tests/suites/test_captains_log.gd"),
	preload("res://tests/suites/test_objectives.gd"),
	preload("res://tests/suites/test_publishing.gd"),
	preload("res://tests/suites/test_harbours.gd"),
	preload("res://tests/suites/test_harbour_chart.gd"),
	preload("res://tests/suites/test_hat.gd"),
	preload("res://tests/suites/test_secret_achievements.gd"),
	preload("res://tests/suites/test_branding.gd"),
	preload("res://tests/suites/test_visual_prototype.gd"),
	preload("res://tests/suites/test_living_world.gd"),
	preload("res://tests/suites/test_harbour_life.gd"),
	preload("res://tests/suites/test_fishing.gd"),
	preload("res://tests/suites/test_fishing2.gd"),
	preload("res://tests/suites/test_sail_trim.gd"),
	preload("res://tests/suites/test_anchorage.gd"),
	preload("res://tests/suites/test_companion_deck.gd"),
	preload("res://tests/suites/test_joy_journey.gd"),
	preload("res://tests/suites/test_coastal_depth.gd"),
	preload("res://tests/suites/test_anchorage_overlay.gd"),
	preload("res://tests/suites/test_magic_anchor.gd"),
	preload("res://tests/suites/test_solar_panels.gd"),
	preload("res://tests/suites/test_sprite_workshop.gd"),
	preload("res://tests/suites/test_cozy_patch.gd"),
	preload("res://tests/suites/test_chartroom_ui.gd"),
	preload("res://tests/suites/test_soundtrack.gd"),
	preload("res://tests/suites/test_cozy_polish.gd"),
	preload("res://tests/suites/test_well_run_ship.gd"),
	preload("res://tests/suites/test_turbocharge.gd"),
	preload("res://tests/suites/test_captains_watch.gd"),
	preload("res://tests/suites/test_localization.gd"),
	preload("res://tests/suites/test_boat_of_your_own.gd"),
	preload("res://tests/suites/test_companion_remarks.gd"),
	preload("res://tests/suites/test_wider_world.gd"),
	preload("res://tests/suites/test_captains_other_life.gd"),
	preload("res://tests/suites/test_academy.gd"),
	preload("res://tests/suites/test_cabin_windows.gd"),
	preload("res://tests/suites/test_steady_hands.gd"),
	preload("res://tests/suites/test_golden_harbours.gd"),
	preload("res://tests/suites/test_galley_and_anchor.gd"),
	preload("res://tests/suites/test_eight_directions.gd"),
	preload("res://tests/suites/test_catch_and_cove_journey.gd"),
	preload("res://tests/suites/test_long_passage.gd"),
	preload("res://tests/suites/test_world_voyage.gd"),
	preload("res://tests/suites/test_diagnostics.gd"),
	preload("res://tests/suites/test_gameplay_flow.gd"),
]

const TEST_SAVE_DIR := "user://test_saves"
const TEST_SETTINGS_PATH := "user://test_settings.cfg"

var passed := 0
var failed := 0
var current_suite := ""
var screenshot_dir := ""
## Run only suites whose file name contains this, or any of a comma-separated
## list (--only=vessels, --only=branding,settings).
var only := ""
## Skip suites whose file name contains any of these (--skip=routing,harbours).
var skip := PackedStringArray()
var _failures: PackedStringArray = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshots="):
			screenshot_dir = arg.trim_prefix("--screenshots=")
		elif arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
		elif arg.begins_with("--skip="):
			skip = arg.trim_prefix("--skip=").split(",", false)
	_run.call_deferred()


func _exit_tree() -> void:
	# The gameplay suite ends by quitting the app: drop the wind fixture (a
	# lambda bound to this node) before this node goes away.
	WindField.clear_default()


func _run() -> void:
	_reset_scratch_files()
	SaveManager.save_dir = TEST_SAVE_DIR
	# The diagnostic log of a test run goes to its own folder.
	SessionLog.log_dir = "user://test_diagnostics"
	SessionLog.restart()
	SettingsManager.settings_path = TEST_SETTINGS_PATH
	# Sleep, dawn and dusk happen at once in tests (suites that test the
	# presentation switch it back on).
	TimePassage.enabled = false
	# I022: suites sail every boat without buying it (ownership tests turn this off).
	GameSession.test_all_boats_owned = true
	# I022: no First Voyage offer or tips over other suites (test_academy turns it on).
	AcademyGuide.enabled = false
	SettingsManager.load_settings()
	# The suites check the English text; the language suite switches itself.
	SettingsManager.set_language(&"en")
	for script in SUITES:
		if Array(skip).any(func(part: String) -> bool: return script.resource_path.get_file().contains(part)):
			continue
		if not only.is_empty() and not Array(only.split(",")).any(func(part: String) -> bool: return script.resource_path.get_file().contains(part)):
			continue
		use_calm_wind()
		Simulation.sea_encounters = script.resource_path.get_file() in ["test_captains_watch.gd", "test_localization.gd"]
		if not SettingsManager.has_chosen_language() or SettingsManager.get_language() != &"en":
			SettingsManager.set_language(&"en")  # a suite before may have reset the settings
		var suite: Object = script.new()
		current_suite = script.resource_path.get_file().get_basename()
		print("\n=== %s ===" % current_suite)
		await suite.run(self)
	print("\n%d checks passed, %d failed." % [passed, failed])
	for failure in _failures:
		print("  FAILED: ", failure)
	WindField.get_default().test_override = Callable()
	_reset_scratch_files()
	get_tree().quit(1 if failed > 0 else 0)


# --- Fixtures -----------------------------------------------------------------------

## Test fixture: a flat calm everywhere. The vessel then motors at exactly the
## engine speed (5 kn) from departure, so voyage timing tests written for the
## constant-speed model of Iteration 002 keep exact, predictable numbers.
## Suites about wind and sailing set their own wind (and restore this).
func use_calm_wind() -> void:
	set_wind(0.0, 0.0)


## Test fixture: puts the running game aboard `vessel_id` in place (same
## area and spawn point, no boatyard visit) and, given the app, shows it.
## Suites whose walks, coordinates or timings were written for the Wing 33
## (starling_33, the starter boat until 0.100b) board it right after a new
## game; new games themselves start aboard the Arctic Wanderer 26, which
## test_vessels and the all-boats suites cover.
func board(vessel_id: StringName, app: Node = null) -> void:
	var state := GameSession.get_state_snapshot()
	state.vessel_id = vessel_id
	GameSession.replace_state(state)
	if app:
		var before: Node = app.router.current_screen
		app._show_current_boat_area()
		await wait_until(func() -> bool: return app.router.current_screen != before and app.router.current_screen.is_inside_tree())
		await physics_frames(3)


## Test fixture: the same wind everywhere, at all times.
func set_wind(from_deg: float, speed_kn: float) -> void:
	WindField.get_default().test_override = func(_geo: Vector2, _time: float) -> WindField.Sample:
		return WindField.Sample.make(from_deg, speed_kn)
	Simulation.invalidate_estimates()


# --- Assertions ---------------------------------------------------------------------

func check(condition: bool, description: String) -> bool:
	if condition:
		passed += 1
		print("  ok   ", description)
	else:
		failed += 1
		_failures.append("[%s] %s" % [current_suite, description])
		print("  FAIL ", description)
	return condition


func check_eq(actual: Variant, expected: Variant, description: String) -> bool:
	var ok: bool = actual == expected
	if not ok:
		description += "  (expected %s, got %s)" % [str(expected), str(actual)]
	return check(ok, description)


# --- Helpers -------------------------------------------------------------------------

func frames(count := 1) -> void:
	for i in count:
		await get_tree().process_frame


func physics_frames(count := 1) -> void:
	for i in count:
		await get_tree().physics_frame


## Waits until `condition` returns true or `timeout` seconds pass.
func wait_until(condition: Callable, timeout := 3.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await get_tree().process_frame
	return true


## Sends an action press + release through the real input pipeline.
func press_action(action: StringName) -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		get_viewport().push_input(event, true)
	await frames(2)


## Holds an action (as polled by Input.get_vector) for `seconds`.
## Presses and releases a physical key (keys that are not input actions, e.g. F9).
func press_key(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		get_viewport().push_input(event, true)
	await frames(2)


func hold_actions(actions: Array, seconds: float) -> void:
	for action in actions:
		Input.action_press(action)
	await get_tree().create_timer(seconds, true, true).timeout
	for action in actions:
		Input.action_release(action)
	await physics_frames(2)


## Clicks a Control with the mouse at its centre, like a player would.
func click(control: Control) -> void:
	var position := control.get_global_transform_with_canvas() * (control.size / 2.0)
	await click_at(position)


func click_at(position: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	get_viewport().push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.position = position
		event.global_position = position
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button == MOUSE_BUTTON_LEFT else 0
		get_viewport().push_input(event, true)
	await frames(2)


## A calculated sea route between two catalog ports (for tests).
func make_route(origin_id: StringName, destination_id: StringName, waypoints: Array[Vector2] = []) -> PlannedRoute:
	var origin := PortCatalog.get_default().get_port(origin_id)
	return SeaRouter.get_default().plan_route(origin_id, origin.get_geo_position(), waypoints, destination_id).route


func screenshot(file_name: String) -> void:
	if screenshot_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	image.save_png(screenshot_dir.path_join(file_name + ".png"))


func _reset_scratch_files() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	if dir.dir_exists("test_saves"):
		for file in DirAccess.get_files_at(TEST_SAVE_DIR):
			DirAccess.remove_absolute(TEST_SAVE_DIR.path_join(file))
		for sub in DirAccess.get_directories_at(TEST_SAVE_DIR):
			DirAccess.remove_absolute(TEST_SAVE_DIR.path_join(sub))
	if FileAccess.file_exists(TEST_SETTINGS_PATH):
		DirAccess.remove_absolute(TEST_SETTINGS_PATH)
