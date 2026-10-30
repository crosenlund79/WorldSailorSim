class_name NewGameMenu
extends ModalPanel
## Starts a new game: the Captain's name (optional; Regions and Harbours
## 2026), the difficulty (Standard preselected; DifficultyPicker, I022), then
## Start.
##
## I025 (A Little More Room Aboard): a new game begins without a companion -
## just the Captain, the boat and the sea. Animals are met on the way (a
## small box on a dock, DockEncounters) and may be welcomed aboard; there is
## no companion to choose here, and nothing else in its place.

signal start_requested(level: StringName, captain_name: String)

var difficulty: DifficultyPicker
## Regions and Harbours 2026: the Captain's own name (optional).
var captain_name: LineEdit


func _ready() -> void:
	difficulty = DifficultyPicker.new()
	var buttons := $Center/Panel/VBox/Buttons as Control
	buttons.add_sibling(difficulty)
	buttons.get_parent().move_child(difficulty, buttons.get_index())
	var heading := Label.new()
	heading.name = "DifficultyQuestion"
	heading.text = "How forgiving should the sea be?"
	difficulty.add_sibling(heading)
	heading.get_parent().move_child(heading, difficulty.get_index())
	captain_name = LineEdit.new()
	captain_name.name = "CaptainName"
	captain_name.placeholder_text = "Your name, Captain (optional)"
	captain_name.max_length = SessionState.CAPTAIN_NAME_MAX
	heading.add_sibling(captain_name)
	heading.get_parent().move_child(captain_name, heading.get_index())
	captain_name.text_submitted.connect(func(_text: String) -> void: %StartButton.pressed.emit())
	%StartButton.pressed.connect(func() -> void: start_requested.emit(difficulty.level, captain_name.text))
	%CancelButton.pressed.connect(close)


func focus_default() -> void:
	%StartButton.grab_focus()
