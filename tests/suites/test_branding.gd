extends RefCounted
## Visual Identity V01, Checkpoint C: the provisional name Little Captain's
## Hat, the version convention (0.100a), the display font (Patrick Hand, used
## sparingly; Barlow stays the functional font), the game's own save folder
## and the copy-only import of saves from Next Harbor.

const APP_SCENE := preload("res://src/app/app.tscn")
const LEGACY_DIR := "user://test_legacy_userdata"
const PATRICK := "res://assets/fonts/PatrickHand-Regular.ttf"
const BARLOW := "res://assets/fonts/Barlow-Regular.ttf"
## Real Horizon: display and heading type is Barlow Condensed (instrument lettering).
const CONDENSED_MEDIUM := "res://assets/fonts/BarlowCondensed-Medium.ttf"
const CONDENSED_SEMIBOLD := "res://assets/fonts/BarlowCondensed-SemiBold.ttf"

var t: Node
var app: Node


func run(runner: Node) -> void:
	t = runner
	_test_name_and_version()
	_test_save_folder()
	_test_fonts_and_licence()
	_test_legacy_import()
	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	await _test_main_menu()
	await _test_import_from_main_menu()
	app.start_new_game()
	await _settle()
	await _test_typography_in_game()
	app.queue_free()
	await t.frames(2)
	GameSession.end_session()
	LegacySaves.legacy_dir_override = ""
	_clean_legacy()


func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)


func _font_path(control: Control) -> String:
	var font := control.get_theme_font(&"font")
	if font is FontVariation:
		font = (font as FontVariation).base_font
	return font.resource_path if font else ""


func _test_name_and_version() -> void:
	t.check_eq(ProjectSettings.get_setting("application/config/name"), "Little Captain's Hat", "[brand] the game is called Little Captain's Hat")
	t.check(String(ProjectSettings.get_setting("application/config/description")).contains("Next Harbor"),
		"[brand] the description says it was developed as Next Harbor")
	t.check_eq(GameVersion.DISPLAY, "0.112a", "[version] this release is 0.112a")
	t.check_eq(ProjectSettings.get_setting("application/config/version"), GameVersion.DISPLAY,
		"[version] project.godot carries the same version (saves record it)")
	t.check(RegEx.create_from_string("^0\\.\\d{3}[a-z]$").search(GameVersion.DISPLAY) != null,
		"[version] it follows the owner's convention 0.<milestone><letter>")
	t.check_eq(GameVersion.MACHINE, "0.112.1", "[version] a numbers-only form for tools (a = 1)")
	var commit := GameVersion.get_commit()
	t.check(commit.is_empty() or RegEx.create_from_string("^[0-9a-f]{7}$").search(commit) != null,
		"[version] the commit is read from the checkout without running git (%s)" % (commit if commit else "unknown"))
	t.check(GameVersion.describe().begins_with("0.112a"), "[version] describe(): %s" % GameVersion.describe())
	t.check_eq(SaveManager.SAVE_VERSION, 12, "[version] the save format has its own version (12), not the game's")
	t.check_eq(String(ProjectSettings.get_setting("application/config/icon")), "res://assets/branding/little_captains_hat_icon.svg",
		"[brand] the window icon is the hat")
	for file in ["little_captains_hat_logo.svg", "little_captains_hat_logo_on_light.svg", "little_captains_hat_icon.svg",
			"little_captains_hat_symbol.svg", "png/little_captains_hat_logo_480.png"]:
		t.check(FileAccess.file_exists("res://assets/branding/" + file), "[brand] %s exists" % file)
	t.check(FileAccess.file_exists("res://assets/branding/next_harbor_logo.svg"), "[brand] the old Next Harbor logo is kept for history")


func _test_save_folder() -> void:
	t.check(ProjectSettings.get_setting("application/config/use_custom_user_dir") == true
		and ProjectSettings.get_setting("application/config/custom_user_dir_name") == "Little Captains Hat",
		"[saves] the game keeps its files in its own fixed folder, Little Captains Hat")
	t.check(OS.get_user_data_dir().ends_with("Little Captains Hat"), "[saves] user:// is that folder (%s)" % OS.get_user_data_dir())
	LegacySaves.legacy_dir_override = ""
	var legacy := LegacySaves.get_legacy_user_dir()
	t.check(legacy.ends_with("app_userdata/Next Harbor") and legacy != OS.get_user_data_dir(),
		"[saves] Next Harbor's folder is a different one, only ever read (%s)" % legacy)
	t.check_eq(SaveManager.FORMAT_ID, "next_harbor_save", "[saves] the file format id is unchanged, so old saves stay valid")


func _test_fonts_and_licence() -> void:
	t.check(FileAccess.file_exists(PATRICK), "[fonts] Patrick Hand is bundled")
	var licence := FileAccess.get_file_as_string("res://assets/fonts/OFL-PatrickHand.txt")
	t.check(licence.contains("SIL Open Font License") and licence.contains("Patrick Wagesreiter"),
		"[fonts] with its licence (SIL OFL 1.1, Patrick Wagesreiter)")
	t.check(FileAccess.get_file_as_string("res://assets/fonts/README.md").contains("OFL-PatrickHand.txt"),
		"[fonts] the fonts README names each font, its use and licence")
	var theme := load("res://assets/ui/next_harbor_theme.tres") as Theme
	t.check_eq(theme.default_font.resource_path, BARLOW, "[fonts] Barlow is still the default UI font")
	for variation in [&"DisplayTagline", &"DisplayHeader", &"DisplayName"]:
		var font := theme.get_font(&"font", variation) as FontVariation
		t.check(font != null and font.base_font.resource_path == CONDENSED_MEDIUM and not font.fallbacks.is_empty()
			and font.fallbacks[0].resource_path == BARLOW, "[fonts] %s uses Barlow Condensed, with Barlow as fallback" % variation)
	# Real Horizon: headings are instrument lettering (Barlow Condensed, Barlow
	# fallback); body and muted text stay Barlow.
	for variation in [&"HeaderLabel", &"TitleLabel"]:
		var font := theme.get_font(&"font", variation) as FontVariation
		t.check(font != null and font.base_font.resource_path == CONDENSED_SEMIBOLD and font.fallbacks[0].resource_path == BARLOW,
			"[fonts] %s uses Barlow Condensed, with Barlow as fallback" % variation)
	t.check(FileAccess.get_file_as_string("res://assets/fonts/OFL-BarlowCondensed.txt").contains("SIL Open Font License"),
		"[fonts] Barlow Condensed is bundled with its licence")
	for variation in [&"Label", &"MutedLabel"]:
		var font := theme.get_font(&"font", variation)
		var path := font.resource_path if font else BARLOW
		t.check(path.contains("Barlow"), "[fonts] %s stays Barlow" % variation)


func _write_legacy_save(slot: int, funds: int) -> String:
	GameSession.start_new_session()
	var state := GameSession.get_state_snapshot()
	state.funds = funds
	var session := state.to_dict()
	session.erase("hat")  # Next Harbor (I006) saves are version 9
	var wrapper := {"format": "next_harbor_save", "version": 9, "game_version": "0.1.0",
		"saved_at_unix": 1790000000.0 + slot, "saved_at_utc": "2026-09-21T12:53:20Z", "session": session}
	DirAccess.make_dir_recursive_absolute(LEGACY_DIR.path_join("saves"))
	var path := LEGACY_DIR.path_join("saves/slot_%d.json" % slot)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(wrapper, "\t", true, true))
	file.close()
	GameSession.end_session()
	return path


func _clean_legacy() -> void:
	for slot in range(1, 4):
		var path := LEGACY_DIR.path_join("saves/slot_%d.json" % slot)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(LEGACY_DIR.path_join("saves"))
	DirAccess.remove_absolute(LEGACY_DIR)


func _test_legacy_import() -> void:
	_clean_legacy()
	for slot in range(1, 4):
		SaveManager.delete_slot(slot)
	LegacySaves.legacy_dir_override = LEGACY_DIR
	t.check(LegacySaves.find().is_empty() and LegacySaves.count_importable() == 0, "[import] no Next Harbor folder: nothing offered")
	var a := _write_legacy_save(1, 1111)
	var b := _write_legacy_save(2, 2222)
	var original_a := FileAccess.get_file_as_bytes(a)
	var original_b := FileAccess.get_file_as_bytes(b)
	# Slot 1 is in use here with another game: it must not be overwritten.
	GameSession.start_new_session()
	var mine := GameSession.get_state_snapshot()
	mine.funds = 5
	SaveManager.save_to_slot(1, mine)
	GameSession.end_session()
	var slot1_before := SaveManager.get_slot_bytes(1)
	t.check_eq(LegacySaves.count_importable(), 2, "[import] two Next Harbor saves are found")
	var results := LegacySaves.import_all()
	var targets := {}
	for r in results:
		targets[int(r.slot)] = int(r.target) if r.result == LegacySaves.RESULT_IMPORTED else 0
	t.check_eq(SaveManager.get_slot_bytes(1), slot1_before, "[import] the slot in use (1) is not overwritten")
	t.check(targets[1] == 3 and targets[2] == 2, "[import] old slot 2 goes to free slot 2, old slot 1 to the next free slot (3)")
	t.check(FileAccess.get_file_as_bytes(a) == original_a and FileAccess.get_file_as_bytes(b) == original_b,
		"[import] the Next Harbor files are untouched")
	t.check(SaveManager.get_slot_bytes(2) == original_b and SaveManager.get_slot_bytes(3) == original_a, "[import] the copies are exact")
	var loaded := SaveManager.load_from_slot(3)
	t.check(loaded.is_ok() and loaded.state.funds == 1111 and loaded.state.hat.status == HatState.STORED,
		"[import] an imported I006 (v9) save loads, upgraded in memory (funds €1,111, the original hat)")
	t.check(String(LegacySaves.describe(results)).contains("The originals are unchanged"), "[import] the result is explained: %s" % LegacySaves.describe(results))
	t.check_eq(LegacySaves.count_importable(), 0, "[import] afterwards nothing is offered again")
	var again := LegacySaves.import_all()
	t.check(again.all(func(r: Dictionary) -> bool: return r.result == LegacySaves.RESULT_ALREADY), "[import] importing again copies nothing (already imported)")
	# A third old save with every slot in use: skipped, nothing overwritten.
	_write_legacy_save(3, 3333)
	var before := [SaveManager.get_slot_bytes(1), SaveManager.get_slot_bytes(2), SaveManager.get_slot_bytes(3)]
	var full := LegacySaves.import_all()
	var skipped := full.filter(func(r: Dictionary) -> bool: return r.result == LegacySaves.RESULT_NO_FREE_SLOT)
	t.check(skipped.size() == 1 and [SaveManager.get_slot_bytes(1), SaveManager.get_slot_bytes(2), SaveManager.get_slot_bytes(3)] == before,
		"[import] with every slot in use it is skipped and reported, nothing overwritten")
	t.check(LegacySaves.describe(full).contains("no free slot"), "[import] ...and the player is told")
	for slot in range(1, 4):
		SaveManager.delete_slot(slot)


func _test_main_menu() -> void:
	var menu := app.router.current_screen as MainMenu
	t.check(menu != null, "[brand] the main menu is shown")
	var logo := menu.find_child("Logo", true, false) as TextureRect
	t.check(logo.texture.resource_path == "res://assets/branding/little_captains_hat_logo.svg", "[brand] the main menu shows the new logo")
	var tagline := menu.find_child("Tagline", true, false) as Label
	t.check(tagline.text == "Small boat. Wide world. Hold onto your hat." and _font_path(tagline) == CONDENSED_MEDIUM,
		"[brand] with the tagline, in Barlow Condensed")
	var version := menu.find_child("Version", true, false) as Label
	t.check(version.text.begins_with("Version 0.112a"), "[version] the menu shows the version (%s)" % version.text)
	t.check(_font_path(version) == BARLOW or version.label_settings != null, "[fonts] the version stays in Barlow")
	t.check(_font_path(menu.find_child("NewGameButton", true, false)).contains("Barlow"), "[fonts] menu buttons stay in Barlow")
	t.check(String((menu.find_child("Credits", true, false) as Label).text).contains("Patrick Hand (SIL OFL)"), "[fonts] the credits name both fonts")
	t.check(String(ProjectSettings.get_setting("application/config/name")) == "Little Captain's Hat" and (DisplayServer.get_name() == "headless" or t.get_window().title.begins_with("Little Captain")),
		"[brand] the window title")
	await t.screenshot("130_main_menu_little_captains_hat")
	SettingsManager.set_ui_scale(1.3)
	await t.frames(3)
	var column := menu.find_child("Column", true, false) as Control
	var visible := Rect2(Vector2.ZERO, menu.get_viewport().get_visible_rect().size / 1.3)
	t.check(visible.encloses(Rect2(column.global_position, column.size)), "[fonts] at 130 % interface scale the title screen still fits")
	await t.screenshot("131_main_menu_scale_130")
	SettingsManager.set_ui_scale(1.0)
	await t.frames(2)


func _test_import_from_main_menu() -> void:
	_clean_legacy()
	LegacySaves.legacy_dir_override = LEGACY_DIR
	var menu := app.router.current_screen as MainMenu
	menu.refresh_saves()
	var button := menu.find_child("ImportButton", true, false) as Button
	t.check(not button.visible, "[import] without Next Harbor saves the menu offers no import")
	_write_legacy_save(1, 4444)
	menu.refresh_saves()
	t.check(button.visible, "[import] with a Next Harbor save, the menu offers to import it")
	await t.click(button)
	await t.frames(2)
	var dialog := app.modals.get_top() as ConfirmDialog
	t.check(dialog != null, "[import] it asks first")
	await t.screenshot("132_import_next_harbor_saves")
	if dialog:
		await t.click(dialog.find_child("ConfirmButton", true, false))
		await t.frames(3)
	t.check(SaveManager.load_from_slot(1).is_ok() and SaveManager.load_from_slot(1).state.funds == 4444, "[import] the save was copied into slot 1")
	t.check(not button.visible and not (menu.find_child("ContinueButton", true, false) as Button).disabled,
		"[import] then the button goes away and Continue is available")
	SaveManager.delete_slot(1)
	_clean_legacy()
	LegacySaves.legacy_dir_override = ""
	menu.refresh_saves()


func _test_typography_in_game() -> void:
	var menu: CaptainsLogMenu = app.open_captains_log()
	await t.frames(2)
	t.check_eq(_font_path(menu.find_child("Title", true, false)), CONDENSED_MEDIUM, "[fonts] the Captain's Log title is in instrument lettering")
	t.check_eq(_font_path(menu.find_child("RecentTitle", true, false)), CONDENSED_MEDIUM, "[fonts] so are its section headings")
	t.check(_font_path(menu.find_child("DistanceValue", true, false)).contains("Barlow"), "[fonts] distances stay in Barlow")
	t.check(_font_path(menu.find_child("RenownValue", true, false)).contains("Barlow"), "[fonts] renown figures stay in Barlow")
	await t.screenshot("133_captains_log_display_headings")
	for scale in [1.0, 1.3]:
		SettingsManager.set_ui_scale(scale)
		await t.frames(3)
		var panel := menu.find_child("Panel", true, false) as Control
		var visible := Rect2(Vector2.ZERO, menu.get_viewport().get_visible_rect().size / scale)
		t.check(visible.encloses(Rect2(panel.global_position, panel.size)), "[fonts] the Captain's Log fits the screen at %d %%" % roundi(scale * 100))
	await t.screenshot("134_captains_log_scale_130")
	SettingsManager.set_ui_scale(1.0)
	app.modals.clear()
	await t.frames(2)
	var hud: Hud = app.hud
	for label: Label in hud.find_children("*", "Label", true, false):
		# Headings (the area name) are maritime since the Captain's Chartroom pass.
		if label.theme_type_variation in [&"HeaderLabel", &"TitleLabel"]:
			continue
		if not _font_path(label).contains("Barlow"):
			t.check(false, "[fonts] HUD label %s is not Barlow" % label.name)
			return
	t.check(true, "[fonts] every HUD label (time, wind, money, food and water) stays in Barlow")
