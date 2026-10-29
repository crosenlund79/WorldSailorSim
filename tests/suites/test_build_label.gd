extends RefCounted
## The development build identifier (bottom right, "BH · i027 · DEV ·
## 1a2b3c4"): one authoritative source (GameVersion), the iteration this
## checkout belongs to (never older than its newest iteration report, never
## invented), stage suffixes, exactly one label through every screen change,
## in the corner at every UI scale, never in the way of the mouse or the
## keyboard, and switched off for a public export.

const APP_SCENE := preload("res://src/app/app.tscn")
const LABEL_PATTERN := "^BH · i\\d{3}(_\\d{2})? · (DEV|TEST)( · [0-9a-f]{7})?$"

var t: Node
var app: Node


func run(runner: Node) -> void:
	t = runner
	_test_metadata()
	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	await _test_everywhere()
	await _test_scale_and_input()
	_test_public_release()
	SettingsManager.set_ui_scale(1.0)
	app.queue_free()
	await t.frames(2)
	GameSession.end_session()


func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)


func _labels() -> Array[Node]:
	return t.get_tree().root.find_children("BuildLabel", "Label", true, false)


func _test_metadata() -> void:
	var label := GameVersion.build_label()
	t.check(RegEx.create_from_string(LABEL_PATTERN).search(label) != null, "[metadata] the label: '%s'" % label)
	t.check(GameVersion.CHANNEL in GameVersion.CHANNELS, "[metadata] the channel is DEV or TEST (%s)" % GameVersion.CHANNEL)
	t.check_eq(GameVersion.format_checkpoint("i042", ""), "i042", "[metadata] an iteration")
	t.check_eq(GameVersion.format_checkpoint("i042", "02"), "i042_02", "[metadata] with an internal stage: i042_02")
	t.check_eq(GameVersion.format_checkpoint("", "02"), "", "[metadata] no iteration known: nothing invented")
	# This checkout's iteration: the newest iteration report in it, or the
	# next one while that is being developed - so a historical checkout names
	# itself and a stale number fails here.
	var newest := 0
	for dir_name in DirAccess.get_directories_at("res://docs/iterations"):
		var m := RegEx.create_from_string("^i(\\d{3})$").search(dir_name)
		if m and FileAccess.file_exists("res://docs/iterations/%s/ITERATION_%d_REPORT.md" % [dir_name, int(m.get_string(1))]):
			newest = maxi(newest, int(m.get_string(1)))
	var own := int(GameVersion.ITERATION.trim_prefix("i"))
	t.check(newest > 0 and (own == newest or own == newest + 1),
		"[metadata] %s matches this checkout's history (newest report i%03d)" % [GameVersion.ITERATION, newest])
	t.check(GameVersion.shows_build_label(), "[metadata] shown in development builds (the project setting)")


func _test_everywhere() -> void:
	t.check_eq(_labels().size(), 1, "[screens] one label on the main menu")
	var label := _labels()[0] as Label
	t.check_eq(label.text, GameVersion.build_label(), "[screens] it shows GameVersion.build_label()")
	await t.screenshot("build_label_main_menu")
	app.start_new_game()
	await _settle()
	t.check_eq(_labels().size(), 1, "[screens] one label in the game")
	await t.screenshot("build_label_gameplay")
	for i in 3:
		app._on_area_change_requested(&"exterior", &"from_cabin")
		await _settle()
		app._on_area_change_requested(&"interior", &"from_deck")
		await _settle()
	app.open_chart()
	await _settle()
	app.close_chart()
	await _settle()
	t.check(_labels().size() == 1 and label.is_visible_in_tree(), "[screens] still exactly one after deck/cabin round trips and the chart")
	app.open_pause_menu()
	await t.frames(3)
	t.check(_labels().size() == 1 and label.is_visible_in_tree(), "[screens] visible over the pause menu")
	await t.screenshot("build_label_paused")
	app.modals.clear()
	app.show_main_menu()
	await _settle()
	t.check(_labels().size() == 1 and label.is_visible_in_tree() and label.text == GameVersion.build_label(), "[screens] back at the menu: the same one")


func _corner_gap(label: Label) -> Vector2:
	var rect := label.get_global_rect()
	var layer := label.get_canvas_layer_node()
	var scale := layer.scale.x if layer else 1.0
	var screen := label.get_viewport().get_visible_rect().size
	return screen - (rect.end * scale)


func _test_scale_and_input() -> void:
	var label := _labels()[0] as Label
	for ui_scale in [1.0, 1.5, 0.8]:
		SettingsManager.set_ui_scale(ui_scale)
		await t.frames(3)
		var gap := _corner_gap(label)
		t.check(gap.x >= 0.0 and gap.y >= 0.0 and gap.x < 40.0 and gap.y < 30.0,
			"[layout] UI scale %.1f: in the bottom-right corner, inside the window (gap %s)" % [ui_scale, gap.round()])
	SettingsManager.set_ui_scale(1.0)
	await t.frames(2)
	# A resized window (rendered runs only: a headless window has no size).
	if DisplayServer.get_name() != "headless":
		var window := t.get_window()
		var size := window.size
		window.size = Vector2i(1280, 720)
		await t.frames(6)
		var gap := _corner_gap(label)
		t.check(gap.x >= 0.0 and gap.y >= 0.0 and gap.x < 40.0 and gap.y < 30.0, "[layout] window 1280 × 720: still in the corner (gap %s)" % gap.round())
		await t.screenshot("build_label_resized_1280x720")
		window.size = size
		await t.frames(6)
	var root := label.get_parent() as Control
	t.check(label.mouse_filter == Control.MOUSE_FILTER_IGNORE and root.mouse_filter == Control.MOUSE_FILTER_IGNORE and label.focus_mode == Control.FOCUS_NONE,
		"[input] it ignores the mouse and never takes focus")
	t.check(label.auto_translate_mode == Node.AUTO_TRANSLATE_MODE_DISABLED, "[input] never translated (an identifier)")


func _test_public_release() -> void:
	var before: Variant = ProjectSettings.get_setting(GameVersion.SHOW_LABEL_SETTING, true)
	ProjectSettings.set_setting(GameVersion.SHOW_LABEL_SETTING, false)
	t.check(not GameVersion.shows_build_label() and BuildLabel.create_layer() == null, "[public] switched off, no label is made")
	ProjectSettings.set_setting(GameVersion.SHOW_LABEL_SETTING, before)
	var project := FileAccess.get_file_as_string("res://project.godot")
	t.check(project.contains("config/show_build_label.public_release=false"), "[public] an export with the 'public_release' feature hides it")
	var layer := BuildLabel.create_layer()
	t.check(layer != null, "[public] on again for development")
	if layer:
		layer.free()
