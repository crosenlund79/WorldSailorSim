class_name ActionWheel
extends ModalPanel
## The action wheel (Iteration 17): Q opens a small ring of the actions that
## make sense where the captain is (at the helm underway, in the cabin, at
## anchor, in harbour). Arrow keys or A/D move round it, E / Enter / Space
## chooses, Q or Esc closes; the mouse works too. It is a modal: the game
## pauses for the moment it is open and nothing under it reacts. It offers
## existing actions only; it is not a new command system.
##
## Items: [{"id", "label", "action": Callable}] given by the App (see
## App.get_wheel_actions()); an on/off item also has "checked": a Callable
## returning whether it is on now, shown as a theme check box (never a copy
## of the state).

signal action_chosen(id: StringName)

const RADIUS := 150.0
const ITEM_SIZE := Vector2(190, 46)

var items: Array[Dictionary] = []
var _buttons: Array[Button] = []
var _selected := 0
var _title: Label


func setup(actions: Array[Dictionary], title := "Actions") -> void:
	items = actions
	if _title:
		_title.text = title
	else:
		set_meta(&"title", title)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = UiTheme.color(&"backdrop")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_title = Label.new()
	_title.name = "Title"
	_title.text = String(get_meta(&"title", "Actions"))
	_title.theme_type_variation = &"HeaderLabel"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title)
	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "←/→ choose  ·  E or Enter use  ·  Q or Esc close"
	hint.theme_type_variation = &"MutedLabel"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)
	for i in items.size():
		var button := Button.new()
		button.name = "Action_%s" % items[i].id
		button.text = items[i].label
		if items[i].has("checked") and (items[i].checked as Callable).is_valid():
			var on: bool = (items[i].checked as Callable).call()
			button.icon = get_theme_icon(&"checked" if on else &"unchecked", &"CheckBox")
			button.set_meta(&"checked", on)
			button.tooltip_text = "On: choose to switch it off" if on else "Off: choose to switch it on"
		button.size = ITEM_SIZE
		button.custom_minimum_size = ITEM_SIZE
		button.pressed.connect(choose.bind(i))
		button.mouse_entered.connect(select.bind(i))
		button.focus_entered.connect(func() -> void: _selected = i)
		add_child(button)
		_buttons.append(button)
	resized.connect(_layout)
	_layout.call_deferred()


func _layout() -> void:
	var centre := size / 2.0
	var radii := wheel_radii(_buttons.size(), size)
	_title.position = centre - Vector2(150, radii.y + 78.0)
	_title.size = Vector2(300, 36)
	var hint := get_node("Hint") as Label
	hint.position = centre + Vector2(-260, radii.y + 50.0)
	hint.size = Vector2(520, 30)
	for i in _buttons.size():
		var angle := -PI / 2.0 + TAU * i / maxf(_buttons.size(), 1)
		_buttons[i].position = centre + Vector2(cos(angle), sin(angle)) * radii - ITEM_SIZE / 2.0


## The wheel's ellipse for `count` items in `area` (I027: under way it holds
## up to a dozen): wide enough that the neighbours at the top clear each
## other's width, never smaller than the classic RADIUS × 1.5 by RADIUS, and
## kept inside the screen with room for the title and the hint.
static func wheel_radii(count: int, area: Vector2) -> Vector2:
	var step := TAU / maxf(count, 1)
	var rx := RADIUS * 1.5
	if count > 1 and sin(step) > 0.05:
		rx = maxf(rx, (ITEM_SIZE.x + 10.0) / sin(minf(step, PI / 2.0)))
	rx = minf(rx, maxf(area.x / 2.0 - ITEM_SIZE.x / 2.0 - 16.0, RADIUS * 1.5))
	var ry := clampf(rx / 1.5, RADIUS, maxf(area.y / 2.0 - 130.0, RADIUS * 0.8))
	return Vector2(rx, ry)


func focus_default() -> void:
	select(0)


func select(index: int) -> void:
	if _buttons.is_empty():
		return
	_selected = posmod(index, _buttons.size())
	_buttons[_selected].grab_focus()


func get_selected_id() -> StringName:
	return items[_selected].id if not items.is_empty() else &""


func choose(index: int) -> void:
	if index < 0 or index >= items.size():
		return
	var action: Callable = items[index].action
	var id: StringName = items[index].id
	close()
	action_chosen.emit(id)
	if action.is_valid():
		action.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var handled := true
	if event.is_action_pressed(&"move_right") or event.is_action_pressed(&"move_down"):
		select(_selected + 1)
	elif event.is_action_pressed(&"move_left") or event.is_action_pressed(&"move_up"):
		select(_selected - 1)
	elif event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_accept"):
		choose(_selected)
	elif event.is_action_pressed(&"action_wheel"):
		close()
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()
