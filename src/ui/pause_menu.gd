class_name PauseMenu
extends ModalPanel
## In-game pause menu. It only reports what the player chose; the
## application flow performs the actions.

signal save_requested
signal log_requested
signal load_requested
signal settings_requested
signal main_menu_requested
## I022: change the difficulty (DifficultyMenu).
signal difficulty_requested
## I022: the Captain's Handbook.
signal handbook_requested
## Development builds only (DevTools): open the developer test panel.
signal dev_tests_requested

@onready var _resume: Button = %ResumeButton


func _ready() -> void:
	_resume.pressed.connect(close)
	%LogButton.pressed.connect(log_requested.emit)
	%SaveButton.pressed.connect(save_requested.emit)
	%LoadButton.pressed.connect(load_requested.emit)
	%SettingsButton.pressed.connect(settings_requested.emit)
	%MainMenuButton.pressed.connect(main_menu_requested.emit)
	# I022: the difficulty, after Settings.
	var difficulty := Button.new()
	difficulty.name = "DifficultyButton"
	difficulty.text = "Difficulty…"
	difficulty.custom_minimum_size = (%SettingsButton as Button).custom_minimum_size
	difficulty.pressed.connect(difficulty_requested.emit)
	%SettingsButton.add_sibling(difficulty)
	var handbook := Button.new()
	handbook.name = "HandbookButton"
	handbook.text = "Captain's Handbook (F1)"
	handbook.custom_minimum_size = difficulty.custom_minimum_size
	handbook.pressed.connect(handbook_requested.emit)
	difficulty.add_sibling(handbook)
	# Developer tests: added only where the developer tools are enabled, so
	# a player's build has no such button at all.
	if DevTools.is_enabled():
		var dev := Button.new()
		dev.name = "DevTestsButton"
		dev.text = "Developer tests (F10)"
		dev.pressed.connect(dev_tests_requested.emit)
		%MainMenuButton.get_parent().add_child(dev)


func focus_default() -> void:
	_resume.grab_focus()
