class_name DifficultyPicker
extends VBoxContainer
## Relaxed / Standard / Seasoned Captain as three buttons, with a line saying
## what the chosen level changes (I022). Used by the New Game menu and by the
## Difficulty dialog of the pause menu (DifficultyMenu).

signal changed(level: StringName)

var level: StringName = Difficulty.STANDARD

var _buttons := {}
var _text: Label


func _init() -> void:
	name = "DifficultyPicker"
	add_theme_constant_override(&"separation", 8)
	var row := HBoxContainer.new()
	row.name = "Levels"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 12)
	add_child(row)
	var group := ButtonGroup.new()
	for id in Difficulty.LEVELS:
		var button := Button.new()
		button.name = String(id).capitalize()
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(190, 44)
		button.pressed.connect(select.bind(id))
		row.add_child(button)
		_buttons[id] = button
	_text = Label.new()
	_text.name = "Description"
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(560, 0)
	_text.theme_type_variation = &"MutedLabel"
	add_child(_text)


func _ready() -> void:
	select(level)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		select(level)


## Shows `id` as chosen (without announcing it).
func select(id: StringName) -> void:
	level = Difficulty.valid(id)
	for key: StringName in _buttons:
		var button := _buttons[key] as Button
		button.text = Difficulty.display_name(key)
		button.set_pressed_no_signal(key == level)
	_text.text = Difficulty.describe(level)
	changed.emit(level)
