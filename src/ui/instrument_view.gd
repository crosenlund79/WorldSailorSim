class_name InstrumentView
extends ModalPanel
## Marine electronics (I026 stage 03): the focused instrument view. The
## fitted package's units enlarged on a piece of the cockpit bulkhead, the
## way they look at the helm, with their pages:
##
##   Classic   the three dials and the LCD repeater; its keys choose the
##             repeater's page (route, next turn, weather, sail trim)
##   Modern    the three displays; each has its own page keys
##   Offshore  the multifunction display; its keys choose the layout
##             (overview, sailing, navigation, weather)
##
## Under the units the readouts in words (the next leg's forecast, the trim,
## the outlook), and a selector for the packages the Captain owns (fitted to
## the boat aboard at once; the chandlery sells the others). Opened from the
## HUD's instruments, I, or the action wheel; Esc closes. Reads one
## InstrumentData a few times a second, like the HUD.

const Face := preload("res://src/electronics/instrument_face.gd")
const REFRESH_SECONDS := 0.25
## The enlarged sizes (UI pixels).
const DIAL := 268.0
const GAP := 18.0
const LCD_HEIGHT := 118.0
const MFD_SIZE := Vector2(860.0, 430.0)
## The bulkhead the units are mounted on: gelcoat by day, dim at night.
const GELCOAT := Color("#CFD1CA")
const GELCOAT_NIGHT := Color("#262D31")

## The Classic repeater's page (kept for the game run).
static var lcd_page := "route"

var package: InstrumentPackage
var data := InstrumentData.new()
var read_count := 0

var _devices: VBoxContainer
var _bulkhead: PanelContainer
var _bulkhead_style: StyleBoxFlat
var _units: Array[Control] = []
var _keys: Array[Button] = []
var _lines := {}
var _selector: OptionButton
var _model: Label
var _hint: Label
var _refresh := 0.0


func _ready() -> void:
	name = "InstrumentView"
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.03, 0.05, 0.06, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 12)
	panel.add_child(box)
	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override(&"separation", 14)
	box.add_child(header)
	var title := Label.new()
	title.name = "Title"
	title.text = "Instruments"
	title.theme_type_variation = &"HeaderLabel"
	header.add_child(title)
	_model = Label.new()
	_model.name = "Model"
	_model.theme_type_variation = &"MutedLabel"
	_model.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_model.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_model)
	var fitted := Label.new()
	fitted.name = "FittedCaption"
	fitted.text = "Fitted"
	fitted.theme_type_variation = &"MutedLabel"
	fitted.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(fitted)
	_selector = OptionButton.new()
	_selector.name = "Package"
	_selector.custom_minimum_size = Vector2(230, 0)
	_selector.tooltip_text = "The instrument packages you own: fitted to this boat at once"
	_selector.item_selected.connect(_on_package_selected)
	header.add_child(_selector)
	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "Close"
	close_button.pressed.connect(close)
	header.add_child(close_button)
	_bulkhead = PanelContainer.new()
	_bulkhead.name = "Bulkhead"
	_bulkhead_style = StyleBoxFlat.new()
	_bulkhead_style.set_corner_radius_all(6)
	_bulkhead_style.content_margin_left = 26
	_bulkhead_style.content_margin_right = 26
	_bulkhead_style.content_margin_top = 22
	_bulkhead_style.content_margin_bottom = 18
	_bulkhead.add_theme_stylebox_override(&"panel", _bulkhead_style)
	box.add_child(_bulkhead)
	_devices = VBoxContainer.new()
	_devices.name = "Devices"
	_devices.alignment = BoxContainer.ALIGNMENT_CENTER
	_devices.add_theme_constant_override(&"separation", 12)
	_bulkhead.add_child(_devices)
	var readouts := GridContainer.new()
	readouts.name = "Readouts"
	readouts.columns = 2
	readouts.add_theme_constant_override(&"h_separation", 14)
	readouts.add_theme_constant_override(&"v_separation", 2)
	box.add_child(readouts)
	for key: String in ["turn", "next_leg", "propulsion", "trim", "outlook"]:
		var caption := Label.new()
		caption.name = "Caption_%s" % key
		caption.theme_type_variation = &"MutedLabel"
		caption.add_theme_font_size_override(&"font_size", 16)
		caption.text = {"turn": "Next turn", "next_leg": "Next leg", "propulsion": "Sails and engine", "trim": "Sail trim", "outlook": "Outlook"}[key]
		readouts.add_child(caption)
		var value := Label.new()
		value.name = "Value_%s" % key
		value.add_theme_font_size_override(&"font_size", 17)
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value.custom_minimum_size = Vector2(640, 0)
		readouts.add_child(value)
		_lines[key] = [caption, value]
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.theme_type_variation = &"MutedLabel"
	_hint.add_theme_font_size_override(&"font_size", 15)
	_hint.text = "More instrument packages are sold at a chandlery."
	box.add_child(_hint)
	GameSession.instruments_changed.connect(_rebuild)
	_rebuild()
	refresh()


## The package's units, laid out afresh (after fitting another package).
func _rebuild() -> void:
	package = GameSession.get_instrument_package()
	_model.text = package.model
	for child in _devices.get_children():
		child.queue_free()
	_units.clear()
	_keys.clear()
	match package.units:
		InstrumentPackage.UNITS_DIALS:
			var row := _row(_devices)
			for kind in ["dial_speed", "dial_heading", "dial_wind"]:
				_unit(row, kind, 0, Vector2(DIAL, DIAL))
			_unit(_devices, "lcd", 0, Vector2(DIAL * 3.0 + GAP * 2.0, LCD_HEIGHT))
			var keys := _row(_devices)
			for page in package.pages:
				_key(keys, Face.page_title(page), page == lcd_page, func() -> void:
					lcd_page = page
					_refresh_keys()
					refresh(), page)
		InstrumentPackage.UNITS_DISPLAYS:
			var row := _row(_devices)
			for i in package.default_pages.size():
				var column := VBoxContainer.new()
				column.add_theme_constant_override(&"separation", 8)
				row.add_child(column)
				_unit(column, "page", i, Vector2(DIAL, DIAL))
				var keys := _row(column)
				keys.add_theme_constant_override(&"separation", 6)
				var previous := _key(keys, "◀", false, _step_page.bind(i, -1), "prev_%d" % i)
				previous.tooltip_text = "Previous page"
				var following := _key(keys, "▶", false, _step_page.bind(i, 1), "next_%d" % i)
				following.tooltip_text = "Next page"
		_:
			_unit(_devices, "mfd", 0, MFD_SIZE)
			var keys := _row(_devices)
			for page in package.pages:
				_key(keys, Face.page_title(page), page == _pages()[0], func() -> void: GameSession.set_instrument_page(0, page), page)
	_fill_selector()
	_refresh = 0.0


func _row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", int(GAP))
	parent.add_child(row)
	return row


func _unit(parent: Control, kind: String, index: int, size: Vector2) -> Control:
	var unit := Control.new()
	unit.name = "Unit_%s_%d" % [kind, index]
	unit.custom_minimum_size = size
	unit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	unit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	unit.set_meta(&"kind", kind)
	unit.set_meta(&"index", index)
	unit.draw.connect(_draw_unit.bind(unit))
	parent.add_child(unit)
	_units.append(unit)
	return unit


## A key on the housing (a flat button; the chosen one is lit).
func _key(parent: Control, text: String, lit: bool, action: Callable, id: String) -> Button:
	var key := Button.new()
	key.name = "Key_%s" % id
	key.text = text
	key.toggle_mode = id in package.pages
	key.set_pressed_no_signal(lit)
	key.set_meta(&"page", id)
	key.custom_minimum_size = Vector2(48, 34)
	key.add_theme_font_size_override(&"font_size", 15)
	key.pressed.connect(action)
	parent.add_child(key)
	_keys.append(key)
	return key


func get_units() -> Array[Control]:
	return _units


func get_key(id: String) -> Button:
	for key in _keys:
		if String(key.get_meta(&"page")) == id:
			return key
	return null


func _pages() -> Array[String]:
	return GameSession.get_instruments().get_pages(package)


## Display `index` one page on (Modern).
func _step_page(index: int, step: int) -> void:
	var choices := package.slot_pages(index)
	var at := choices.find(_pages()[index])
	GameSession.set_instrument_page(index, choices[posmod(at + step, choices.size())])
	refresh()


func _refresh_keys() -> void:
	for key in _keys:
		var page := String(key.get_meta(&"page"))
		if page in package.pages:
			key.set_pressed_no_signal(page == (lcd_page if package.units == InstrumentPackage.UNITS_DIALS else _pages()[0]))
		else:
			key.set_pressed_no_signal(false)


func _fill_selector() -> void:
	_selector.clear()
	var owned := GameSession.get_instruments().owned_ids()
	for id in owned:
		var item := InstrumentPackage.get_package(id)
		_selector.add_item(item.name)
		_selector.set_item_metadata(_selector.item_count - 1, id)
		if id == package.id:
			_selector.select(_selector.item_count - 1)
	_selector.disabled = owned.size() < 2
	_hint.visible = owned.size() < InstrumentPackage.get_ids().size()


func _on_package_selected(index: int) -> void:
	var id := String(_selector.get_item_metadata(index))
	var error := GameSession.fit_instrument_package(id)
	if error != "":
		notify(error)
	else:
		notify(Loc.t("%s fitted to the %s.") % [InstrumentPackage.get_package(id).get_display_name(), GameSession.get_vessel_definition().display_name])


func _draw_unit(unit: Control) -> void:
	var rect := Rect2(Vector2.ZERO, unit.size)
	var night := UiTheme.blend
	var kind := String(unit.get_meta(&"kind"))
	match kind:
		"lcd":
			Face.draw_lcd(unit, rect, package, lcd_page, data, night, true)
		"page":
			Face.draw_page(unit, rect, package, _pages()[int(unit.get_meta(&"index"))], data, night)
		"mfd":
			Face.draw_mfd(unit, rect, package, _pages()[0], data, night)
		_:
			Face.draw_dial(unit, rect, package, kind, data, night)


func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = REFRESH_SECONDS
		refresh()


## A new reading: the units and the readouts.
func refresh() -> void:
	data = InstrumentData.read(true)
	read_count += 1
	_bulkhead_style.bg_color = GELCOAT.lerp(GELCOAT_NIGHT, UiTheme.blend)
	for key: String in _lines:
		var text := data.get_value(key)
		if key == "turn" and text == "":
			text = data.get_value("status")
		(_lines[key][1] as Label).text = text
		for label: Label in _lines[key]:
			label.visible = text != ""
	_refresh_keys()
	for unit in _units:
		unit.queue_redraw()


## The readout lines in words (tests).
func get_value(key: String) -> String:
	return data.get_value(key)


func focus_default() -> void:
	for key in _keys:
		if key.is_visible_in_tree() and (key.button_pressed or not key.toggle_mode):
			key.grab_focus()
			return
	(find_child("CloseButton", true, false) as Button).grab_focus()
