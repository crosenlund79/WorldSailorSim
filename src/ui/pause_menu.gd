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
## Regions and Harbours 2026: the Captain's name was changed here.
signal captain_name_entered(captain_name: String)

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
	_add_captain_name()
	if DevTools.is_enabled():
		var dev := Button.new()
		dev.name = "DevTestsButton"
		dev.text = "Developer tests (F10)" if DevTools.is_editor_build() else "Captain's Tools (F10)"
		dev.pressed.connect(dev_tests_requested.emit)
		%MainMenuButton.get_parent().add_child(dev)


## The Captain's name, editable (Regions and Harbours 2026): kept with this
## game; applied when confirmed or when the field is left.
func _add_captain_name() -> void:
	if not GameSession.is_active():
		return
	var row := HBoxContainer.new()
	row.name = "CaptainNameRow"
	row.add_theme_constant_override(&"separation", 10)
	var label := Label.new()
	label.text = "Captain's name"
	row.add_child(label)
	var field := LineEdit.new()
	field.name = "CaptainName"
	field.text = GameSession.get_captain_name()
	field.placeholder_text = "Not given"
	field.max_length = SessionState.CAPTAIN_NAME_MAX
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.text_submitted.connect(func(text: String) -> void: captain_name_entered.emit(text))
	field.focus_exited.connect(func() -> void: captain_name_entered.emit(field.text))
	row.add_child(field)
	%MainMenuButton.get_parent().add_child(row)
	%MainMenuButton.get_parent().move_child(row, %MainMenuButton.get_index())


func focus_default() -> void:
	_resume.grab_focus()
