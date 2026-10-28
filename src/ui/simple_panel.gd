class_name SimplePanel
extends ModalPanel
## A small centred dialog built in code (title, body, a row of buttons), in the
## same style as the other modals. Used by the work and grocery dialogs.

## I024: shown on the cabin laptop's screen (LaptopView) instead of as a
## dialog of its own: no backdrop, no frame, it fills the screen's app area.
## Set before the panel enters the tree.
var embedded := false

var _box: VBoxContainer
var _buttons: HBoxContainer


func _build(title: String, width := 620.0) -> VBoxContainer:
	if embedded:
		var page := PanelContainer.new()
		page.name = "Panel"
		page.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(page)
		_box = VBoxContainer.new()
		_box.add_theme_constant_override("separation", 12)
		page.add_child(_box)
		_label("Title", title, &"HeaderLabel")
		return _box
	var dim := ColorRect.new()
	dim.name = "Dim"  # coloured by UiTheme (the modal backdrop)
	dim.color = Color(0.04, 0.07, 0.09, 0.58)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(width, 0)
	center.add_child(panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 14)
	panel.add_child(_box)
	_label("Title", title, &"HeaderLabel")
	return _box


func _label(node_name: String, text: String, variation: StringName = &"") -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(540, 0)
	_box.add_child(label)
	return label


func _button(node_name: String, text: String, action: Callable, min_width := 150.0) -> Button:
	if _buttons == null:
		_buttons = HBoxContainer.new()
		_buttons.name = "Buttons"
		_buttons.alignment = BoxContainer.ALIGNMENT_END
		_buttons.add_theme_constant_override("separation", 14)
		_box.add_child(_buttons)
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(min_width, 0)
	button.pressed.connect(action)
	_buttons.add_child(button)
	return button
