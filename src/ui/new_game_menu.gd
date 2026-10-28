class_name NewGameMenu
extends ModalPanel
## Starts a new game: the difficulty (Standard preselected; DifficultyPicker,
## I022), then Start.
##
## I025 (A Little More Room Aboard): a new game begins without a companion -
## just the Captain, the boat and the sea. Animals are met on the way (a
## small box on a dock, DockEncounters) and may be welcomed aboard; there is
## no companion to choose here, and nothing else in its place.

signal start_requested(level: StringName)

var difficulty: DifficultyPicker


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
	%StartButton.pressed.connect(func() -> void: start_requested.emit(difficulty.level))
	%CancelButton.pressed.connect(close)


func focus_default() -> void:
	%StartButton.grab_focus()
