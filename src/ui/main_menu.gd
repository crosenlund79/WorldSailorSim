class_name MainMenu
extends UiScaleLayer
## Title screen. It only reports the player's choice; the application flow
## starts or loads games. Continue is enabled only when a valid save exists.

signal new_game_requested
signal continue_requested
signal load_requested
signal settings_requested
signal quit_requested
## Development builds only: the DEV_GUIDES viewer.
signal dev_guides_requested
## Copy the saves from Next Harbor (shown only when there are any to copy).
signal import_requested

@onready var _new_game: Button = %NewGameButton
@onready var _continue: Button = %ContinueButton
@onready var _continue_info: Label = %ContinueInfo
@onready var _load: Button = %LoadButton


func _ready() -> void:
	super._ready()
	# The name and its line come from one place (GameVersion).
	%Logo.texture = load(GameVersion.LOGO_PATH)
	%Tagline.text = GameVersion.TAGLINE
	_new_game.pressed.connect(new_game_requested.emit)
	_continue.pressed.connect(continue_requested.emit)
	_load.pressed.connect(load_requested.emit)
	%SettingsButton.pressed.connect(settings_requested.emit)
	%QuitButton.pressed.connect(quit_requested.emit)
	# Developer resources: only when running from the project in a debug build.
	%DevGuidesButton.visible = DevGuides.is_available()
	%DevGuidesButton.pressed.connect(dev_guides_requested.emit)
	%ImportButton.pressed.connect(import_requested.emit)
	SaveManager.slots_changed.connect(refresh_saves)
	SettingsManager.language_changed.connect(func(_locale: StringName) -> void: refresh_saves())
	refresh_saves()
	focus_default.call_deferred()


func focus_default() -> void:
	_new_game.grab_focus()


func refresh_saves() -> void:
	%Version.text = Loc.t("Version %s") % (GameVersion.describe() if OS.is_debug_build() else GameVersion.DISPLAY)
	%ImportButton.visible = LegacySaves.count_importable() > 0
	var slot := SaveManager.get_most_recent_valid_slot()
	_continue.disabled = slot == 0
	_load.disabled = not _any_slot_used()
	if slot == 0:
		_continue_info.text = "No saved game yet"
	else:
		var info := SaveManager.get_slot_info(slot)
		_continue_info.text = Loc.t("Slot %d  ·  %s  ·  %s") % [
			slot, SaveLoadMenu.format_timestamp(info.saved_at_unix), info.location_name]


func _any_slot_used() -> bool:
	for info in SaveManager.get_all_slot_info():
		if info.status != SaveManager.Status.EMPTY:
			return true
	return false
