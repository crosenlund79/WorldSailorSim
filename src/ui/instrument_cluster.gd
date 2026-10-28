class_name InstrumentCluster
extends VBoxContainer
## Marine electronics (I026 stage 03): the boat's instruments on the HUD,
## in the fitted package's own look (InstrumentPackage, InstrumentFace).
## It replaces the sailing panel and the route panel's sailing lines: the
## speed, the heading, the true wind and its angle, the route (destination,
## distance, ETA), the next turn and, at anchor, the anchor; the next leg's
## forecast, the trim and the weather are on the pages of the focused view.
##
##   Classic   three dials (speed, heading, wind) and the LCD repeater
##   Modern    three displays, each on its chosen page
##   Offshore  the multifunction display on its chosen layout
##
## Shown underway, on deck and in the cabin (the essentials never need a
## walk). It reads one InstrumentData a few times a second (REFRESH_SECONDS)
## and redraws only then, never every frame. A click on an instrument (or I,
## or the action wheel) opens the focused InstrumentView. A new course of
## more than COURSE_CHANGE_DEG gives the heading a short, restrained
## highlight (one gentle pulse with Reduce flashing on), as the sailing panel
## did.

signal view_requested

const Face := preload("res://src/electronics/instrument_face.gd")
const REFRESH_SECONDS := 0.25
const COURSE_CHANGE_DEG := 5.0
## A dial's or display's size on the HUD, the gap between them, and the
## Classic repeater's and the Offshore display's heights.
const UNIT := Face.BASE
const GAP := 8.0
const LCD_HEIGHT := 60.0
const MFD_HEIGHT := 190.0
const WIDTH := UNIT * 3.0 + GAP * 2.0

var package: InstrumentPackage
var data := InstrumentData.new()
## How many readings were taken (tests: a few a second, not every frame).
var read_count := 0
## The heading highlight (0..1), drawn by the units.
var pulse := 0.0:
	set(value):
		pulse = value
		_redraw_units()

var _row: HBoxContainer
var _units: Array[Control] = []
var _status: Label
var _status_style: StyleBoxFlat
var _refresh := 0.0
var _course_key := Vector2i(-1, -1)
var _last_course := -1.0
var _pulse: Tween


func _ready() -> void:
	name = "InstrumentCluster"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", int(GAP))
	alignment = BoxContainer.ALIGNMENT_BEGIN
	_row = HBoxContainer.new()
	_row.name = "Units"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.alignment = BoxContainer.ALIGNMENT_END
	_row.add_theme_constant_override(&"separation", int(GAP))
	add_child(_row)
	_status = Label.new()
	_status.name = "Status"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(WIDTH, 0)
	_status.add_theme_font_size_override(&"font_size", 16)
	_status_style = _status_box()
	_status.add_theme_stylebox_override(&"normal", _status_style)
	_status.visible = false
	add_child(_status)
	GameSession.instruments_changed.connect(_rebuild)
	GameSession.state_replaced.connect(_rebuild)
	_rebuild()
	visible = false


func _status_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(UiTheme.color(&"surface_hud"), 0.82)
	box.set_corner_radius_all(3)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 3
	box.content_margin_bottom = 4
	return box


static func should_show() -> bool:
	return GameSession.is_active() and GameSession.is_underway()


## The fitted package's units, laid out afresh (on fitting another package
## or loading a game).
func _rebuild() -> void:
	package = GameSession.get_instrument_package() if GameSession.is_active() else InstrumentPackage.get_package(InstrumentPackage.CLASSIC)
	for unit in _units:
		unit.queue_free()
	_units.clear()
	var kinds: Array[Array] = []
	match package.units:
		InstrumentPackage.UNITS_DIALS:
			kinds = [["dial_speed", 0], ["dial_heading", 0], ["dial_wind", 0]]
		InstrumentPackage.UNITS_DISPLAYS:
			for i in package.default_pages.size():
				kinds.append(["page", i])
		_:
			kinds = [["mfd", 0]]
	for spec in kinds:
		_add_unit(_row, spec[0], spec[1], Vector2(WIDTH, MFD_HEIGHT) if spec[0] == "mfd" else Vector2(UNIT, UNIT))
	if package.units == InstrumentPackage.UNITS_DIALS:
		var lcd := _add_unit(self, "lcd", 0, Vector2(WIDTH, LCD_HEIGHT))
		move_child(lcd, 1)
	_refresh = 0.0


func _add_unit(parent: Control, kind: String, index: int, size: Vector2) -> Control:
	var unit := Control.new()
	unit.name = "Unit_%s_%d" % [kind, index]
	unit.custom_minimum_size = size
	unit.mouse_filter = Control.MOUSE_FILTER_STOP
	unit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	unit.tooltip_text = "Instruments (I): click for the full view"
	unit.set_meta(&"kind", kind)
	unit.set_meta(&"index", index)
	unit.draw.connect(_draw_unit.bind(unit))
	unit.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			view_requested.emit())
	parent.add_child(unit)
	_units.append(unit)
	return unit


func get_units() -> Array[Control]:
	return _units


## The page (or layout) unit `index` shows (Modern and Offshore).
func get_page(index: int) -> String:
	var pages := GameSession.get_instruments().get_pages(package) if GameSession.is_active() else package.default_pages
	return pages[index] if index < pages.size() else ""


func _draw_unit(unit: Control) -> void:
	var rect := Rect2(Vector2.ZERO, unit.size)
	var night := UiTheme.blend
	var kind := String(unit.get_meta(&"kind"))
	match kind:
		"lcd":
			Face.draw_lcd(unit, rect, package, "route", data, night)
		"page":
			Face.draw_page(unit, rect, package, get_page(int(unit.get_meta(&"index"))), data, night, pulse)
		"mfd":
			Face.draw_mfd(unit, rect, package, get_page(0), data, night, pulse)
		_:
			Face.draw_dial(unit, rect, package, kind, data, night, pulse)


func _redraw_units() -> void:
	for unit in _units:
		unit.queue_redraw()


func _process(delta: float) -> void:
	var show := should_show()
	if visible != show:
		visible = show
		_refresh = 0.0
	if not show:
		return
	_refresh -= delta
	if _refresh > 0.0:
		return
	_refresh = REFRESH_SECONDS
	refresh()


## Takes a new reading and redraws (a few times a second).
func refresh() -> void:
	var weather := false
	for i in _units.size():
		weather = weather or get_page(i) == "weather"
	data = InstrumentData.read(weather)
	read_count += 1
	var status := data.get_value("status") if data.anchored or data.holding else ""
	if _status.text != status:
		_status.text = status
	_status.visible = status != ""
	_status_style.bg_color = Color(UiTheme.color(&"surface_hud"), 0.82)
	_check_course_change()
	_redraw_units()


## A readout as words (the sailing panel's wording), for tests.
func get_value(key: String) -> String:
	return data.get_value(key)


func get_status_text() -> String:
	return _status.text if _status.visible else ""


# --- The course-change highlight --------------------------------------------------------------------

func _check_course_change() -> void:
	var voyage := GameSession.get_voyage()
	if voyage == null or data.anchored or data.holding:
		return
	var key := Vector2i(voyage.revision, GeoMath.segment_index_at(voyage.get_cumulative(), voyage.progress_nm))
	if key == _course_key:
		return
	var first := _course_key.x < 0
	_course_key = key
	var heading := data.heading_deg
	var changed := absf(angle_difference(deg_to_rad(_last_course), deg_to_rad(heading))) > deg_to_rad(COURSE_CHANGE_DEG)
	_last_course = heading
	if not first and changed:
		pulse_heading()


## Tests: whether the heading highlight is running.
func is_pulsing() -> bool:
	return _pulse != null and _pulse.is_running()


func pulse_heading() -> void:
	if _pulse:
		_pulse.kill()
	_pulse = create_tween()
	var gentle := SettingsManager.get_reduce_flashing()
	for i in 1 if gentle else 2:
		_pulse.tween_property(self, ^"pulse", 1.0, 0.35 if not gentle else 0.8)
		_pulse.tween_property(self, ^"pulse", 0.0, 0.45 if not gentle else 1.2)
