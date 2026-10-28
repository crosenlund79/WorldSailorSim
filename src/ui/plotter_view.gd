class_name PlotterView
extends ModalPanel
## Marine electronics (I026 stage 03): the chartplotter at the helm, close
## up. The plotter's screen (ChartPlotter: the coast, the course, the next
## turn, the wind) in the fitted package's housing, with its range keys and
## a data column beside the chart. It is the cockpit plotter, for sailing
## now; courses are still planned at the chart table (or with Charts on the
## action wheel), as before. Opened with P, the action wheel, or at the
## plotter by the helm; Esc closes.

const Face := preload("res://src/electronics/instrument_face.gd")
const PLOT := 520.0
const COLUMN := 250.0
const BEZEL := 26.0
const REFRESH_SECONDS := 0.25

var package: InstrumentPackage
var plotter: ChartPlotter
var data := InstrumentData.new()

var _device: Control
var _column := {}
var _refresh := 0.0


func _ready() -> void:
	name = "PlotterView"
	package = GameSession.get_instrument_package()
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
	header.add_theme_constant_override(&"separation", 14)
	box.add_child(header)
	var title := Label.new()
	title.name = "Title"
	title.text = "Chartplotter"
	title.theme_type_variation = &"HeaderLabel"
	header.add_child(title)
	var model := Label.new()
	model.name = "Model"
	model.theme_type_variation = &"MutedLabel"
	model.text = package.model
	model.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	model.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(model)
	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "Close"
	close_button.pressed.connect(close)
	header.add_child(close_button)
	# The device: the housing drawn behind, the chart and the data column on its glass.
	_device = Control.new()
	_device.name = "Device"
	_device.custom_minimum_size = Vector2(PLOT + COLUMN + BEZEL * 2.0 + 12.0, PLOT + BEZEL * 2.0 + 40.0)
	_device.draw.connect(_draw_device)
	box.add_child(_device)
	plotter = ChartPlotter.new()
	plotter.plot_size = PLOT
	plotter.raster = 192
	plotter.position = Vector2(BEZEL, BEZEL)
	_device.add_child(plotter)
	var column := VBoxContainer.new()
	column.name = "Data"
	column.position = Vector2(BEZEL + PLOT + 12.0, BEZEL + 4.0)
	column.custom_minimum_size = Vector2(COLUMN - 12.0, PLOT - 8.0)
	column.add_theme_constant_override(&"separation", 2)
	_device.add_child(column)
	for key: String in ["speed", "heading", "turn", "wind", "range"]:
		var caption := Label.new()
		caption.name = "Caption_%s" % key
		caption.text = {"speed": "Speed", "heading": "Heading", "turn": "Next turn", "wind": "Wind", "range": "Range"}[key]
		caption.add_theme_font_size_override(&"font_size", 14)
		caption.add_theme_font_override(&"font", Face.font(&"condensed"))
		column.add_child(caption)
		var value := Label.new()
		value.name = "Value_%s" % key
		value.add_theme_font_size_override(&"font_size", 22)
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value.custom_minimum_size = Vector2(COLUMN - 16.0, 0)
		column.add_child(value)
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 8)
		column.add_child(gap)
		_column[key] = [caption, value]
	# The range keys on the bezel, under the chart.
	var keys := HBoxContainer.new()
	keys.name = "Keys"
	keys.position = Vector2(BEZEL, BEZEL * 2.0 + PLOT - 18.0)
	keys.add_theme_constant_override(&"separation", 10)
	_device.add_child(keys)
	for spec in [["ZoomIn", "+", -1, "Closer"], ["ZoomOut", "–", 1, "Farther"]]:
		var key := Button.new()
		key.name = spec[0]
		key.text = spec[1]
		key.tooltip_text = spec[3]
		key.custom_minimum_size = Vector2(56, 36)
		key.pressed.connect(func() -> void:
			plotter.change_range(spec[2])
			refresh())
		keys.add_child(key)
	var hint := Label.new()
	hint.name = "Hint"
	hint.theme_type_variation = &"MutedLabel"
	hint.add_theme_font_size_override(&"font_size", 15)
	hint.text = "Plan a course at the chart table, or with Charts on the action wheel (Q)."
	box.add_child(hint)
	refresh()


func _draw_device() -> void:
	var night := UiTheme.blend
	var rect := Rect2(Vector2.ZERO, _device.size)
	Face.housing(_device, rect, package, night, 10.0)
	Face.box(_device, rect.grow(-4.0), Color(0, 0, 0, 0), 8.0, Color(package.colour_at("housing_edge", night), 0.5), 1.0)
	var glass := Rect2(Vector2(BEZEL - 4.0, BEZEL - 4.0), Vector2(PLOT + COLUMN + 16.0, PLOT + 8.0))
	Face.glass(_device, glass, package.colour_at("screen", night) if package.units != InstrumentPackage.UNITS_DIALS else Color("#0E171C").lerp(Color("#070B0D"), night),
		4.0, night)
	# The maker's mark on the lower bezel, right.
	Face.text_at(_device, Vector2(rect.end.x - BEZEL, rect.end.y - 20.0), "%s  %s" % [InstrumentPackage.brand(), package.model.trim_prefix(InstrumentPackage.brand()).strip_edges().to_upper()],
		12.0, Color(package.colour_at("housing_edge", night), 0.9), &"condensed", 300.0, HORIZONTAL_ALIGNMENT_RIGHT)


func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = REFRESH_SECONDS
		refresh()


func refresh() -> void:
	data = InstrumentData.read()
	var night := UiTheme.blend
	var screen_ink := package.colour_at("ink", night) if package.units != InstrumentPackage.UNITS_DIALS else Color("#E4EAE8").lerp(Color("#C9A08F"), night)
	var accent := package.colour_at("accent", night) if package.units != InstrumentPackage.UNITS_DIALS else Color("#5AA8B8").lerp(Color("#C0503A"), night)
	var values := {
		"speed": "%s kn" % Loc.decimal(data.speed_kn, 1) if data.underway else Loc.t("Moored"),
		"heading": Face.heading_text(data),
		"turn": (Loc.format("%.1f nm  →  %03d°", [float(data.turn.nm), roundi(float(data.turn.next_course))]) if data.has_next_leg()
			else data.get_value("turn") if data.underway else "---"),
		"wind": data.get_value("wind").split("  ·  ")[0],
		"range": Loc.t("%d nm") % roundi(plotter.get_range_nm()),
	}
	for key: String in _column:
		var caption := _column[key][0] as Label
		var value := _column[key][1] as Label
		caption.add_theme_color_override(&"font_color", accent)
		value.add_theme_color_override(&"font_color", screen_ink)
		if value.text != values[key]:
			value.text = values[key]
	_device.queue_redraw()


## The data column's value for `key` (tests).
func get_value(key: String) -> String:
	return (_column[key][1] as Label).text if _column.has(key) else ""


func focus_default() -> void:
	(_device.find_child("ZoomIn", true, false) as Button).grab_focus()
