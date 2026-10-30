extends Node
## Captain Haddock's tools, checked end to end (Regions and Harbours 2026),
## also in an exported build, where the editor's own access is absent. In
## the editor: `godot --path . res://tests/haddock_probe.tscn [-- --out=DIR]`.
## Official export templates refuse a scene path on the command line, so for
## an exported probe build add, for that export only (never committed),
## `run/main_scene.haddock_probe="res://tests/haddock_probe.tscn"` under
## [application] in project.godot and the custom feature "haddock_probe" to
## the export preset; then run the exported binary `-- --out=DIR`.
## Each scenario goes through the game's own New Game window (the name typed
## into its field, Start pressed), the F10 key (a real key event), saves and
## loads, and the pause menu's name field. Prints "HADDOCK {json}": the build
## (editor or exported), every scenario's result and whether it was expected.
## Uses its own save folder and settings file.

const APP_SCENE := preload("res://src/app/app.tscn")

var app: Node
var results: Array = []
var out := ""


func _ready() -> void:
	SaveManager.save_dir = "user://haddock_probe_saves"
	SettingsManager.settings_path = "user://haddock_probe_settings.cfg"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	_run.call_deferred()


func _idle(frames := 6) -> void:
	var guard := 0
	while app.router.is_busy() and guard < 2000:
		guard += 1
		await get_tree().process_frame
	for i in frames:
		await get_tree().process_frame


func _record(scenario: String, got: Variant, expected: Variant) -> void:
	print("  probe: %s -> %s" % [scenario, got])
	results.append({"scenario": scenario, "got": got, "expected": expected, "ok": got == expected})


## A new game through the New Game window with `captain_name` typed in.
func _new_game(captain_name: String) -> void:
	app.modals.clear()
	app.open_new_game_menu()
	await _idle()
	var menu := app.modals.get_top() as NewGameMenu
	menu.captain_name.text = captain_name
	(menu.get_node("%StartButton") as Button).pressed.emit()
	await _idle(12)
	app.modals.clear()  # the opening story, if any
	await _idle()


## Presses F10 (a real key event) and returns whether the panel is then open.
func _f10() -> bool:
	var press := InputEventKey.new()
	press.keycode = KEY_F10
	press.physical_keycode = KEY_F10
	press.pressed = true
	Input.parse_input_event(press)
	var release := press.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)
	await _idle(4)
	return app.modals.get_top() is DevTestPanel


func _shot(name: String) -> void:
	if out.is_empty():
		return
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(out)
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])


func _run() -> void:
	OpeningStory.enabled = false
	AcademyGuide.enabled = false
	app = APP_SCENE.instantiate()
	add_child(app)
	app.router.fade_duration = 0.05
	await _idle()
	var build := {"editor_feature": OS.has_feature("editor"), "debug_build": OS.is_debug_build(),
		"template": OS.has_feature("template"), "editor_access": DevTools.is_editor_build()}
	# 1-5: the exact name, any case and spaces around it; near misses do not.
	for name in ["Haddock", "haddock", "  HADDOCK  ", "Captain Haddock", "Haddock123", "Haddocks", "Archibald", ""]:
		await _new_game(name)
		var expected: bool = name.strip_edges().to_lower() == "haddock" or DevTools.is_editor_build()
		var opened := await _f10()
		_record("New Game as '%s': F10 opens the tools" % name, opened, expected)
		if opened:
			await _shot("tools_" + name.strip_edges().to_lower().replace(" ", "_"))
			_record("  '%s': F10 closes them again" % name, not await _f10(), true)
		app.modals.clear()
	# 6: everywhere aboard and ashore (cabin, deck, quay, chart), as Haddock.
	await _new_game("Haddock")
	var places := {}
	GameSession.enter_boat_area(SessionState.AREA_INTERIOR, &"start")
	app._show_current_boat_area()
	await _idle()
	places["cabin"] = await _f10() and not await _f10()
	GameSession.enter_boat_area(SessionState.AREA_EXTERIOR, &"from_boatyard")
	app._show_current_boat_area()
	await _idle()
	places["deck"] = await _f10() and not await _f10()
	app.open_quay()
	await _idle()
	places["quay"] = await _f10() and not await _f10()
	app.open_chart()
	await _idle()
	places["chart"] = await _f10() and not await _f10()
	_record("Haddock: F10 opens and closes on cabin, deck, quay and chart", places, {"cabin": true, "deck": true, "quay": true, "chart": true})
	GameSession.enter_boat_area(SessionState.AREA_EXTERIOR, &"from_boatyard")
	app._show_current_boat_area()
	await _idle()
	# 7: the panel's heading and a cheat through the game's own systems.
	await _f10()
	var panel := app.modals.get_top() as DevTestPanel
	var heading := ""
	if panel:
		for label in panel.find_children("*", "Label", true, false):
			if (label as Label).theme_type_variation == &"HeaderLabel":
				heading = (label as Label).text
				break
	_record("Haddock: the panel's heading", heading, "DEVELOPER TEST TOOLS" if DevTools.is_editor_build() else "Captain's Tools")
	var money := GameSession.get_funds()
	DevTools.add_money(1000)
	_record("Haddock: + €1,000 goes through the game's money", GameSession.get_funds() - money, 1000)
	app.modals.clear()
	await _idle()
	# 8: save and load keep it; another save without the name decides again.
	SaveManager.save_to_slot(1, GameSession.get_state_snapshot())
	await _new_game("Archibald")
	SaveManager.save_to_slot(2, GameSession.get_state_snapshot())
	app.load_slot(1)
	await _idle()
	_record("Loading Haddock's save: the tools open", await _f10(), true)
	app.modals.clear()
	app.load_slot(2)
	await _idle()
	_record("Loading Archibald's save: they do not", await _f10(), DevTools.is_editor_build())
	app.modals.clear()
	# 9: renaming in the pause menu decides again.
	app.open_pause_menu()
	await _idle()
	var field := app.modals.get_top().find_child("CaptainName", true, false) as LineEdit
	field.text = "haddock"
	field.text_submitted.emit(field.text)
	await _idle()
	await _shot("pause_menu_renamed")
	app.modals.clear()
	await _idle()
	_record("Renamed to 'haddock' in the pause menu: the tools open", await _f10(), true)
	app.modals.clear()
	app.open_pause_menu()
	await _idle()
	field = app.modals.get_top().find_child("CaptainName", true, false) as LineEdit
	field.text = "Captain Haddock"
	field.text_submitted.emit(field.text)
	app.modals.clear()
	await _idle()
	_record("Renamed to 'Captain Haddock': they do not", await _f10(), DevTools.is_editor_build())
	app.modals.clear()
	# 10: not a global setting: the settings file holds no name, and the main menu (no game) offers nothing.
	var settings_text := FileAccess.get_file_as_string(SettingsManager.settings_path)
	_record("The name is not in the settings file", settings_text.to_lower().contains("haddock"), false)
	app.load_slot(1)
	await _idle()
	_record("Haddock's save still opens them after all that", await _f10(), true)
	app.modals.clear()
	var passed := results.filter(func(r: Dictionary) -> bool: return r.ok).size()
	print("HADDOCK ", JSON.stringify({"build": build, "passed": passed, "total": results.size(), "results": results}))
	for slot in [1, 2]:
		SaveManager.delete_slot(slot)
	get_tree().quit()
