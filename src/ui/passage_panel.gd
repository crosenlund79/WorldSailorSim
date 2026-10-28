class_name PassagePanel
extends PanelContainer
## Long Passage (Iteration 16): a compact panel on deck during a long voyage.
## Where the boat is, how far and how long to go, the wind and the outlook,
## the stores and the boat, and the passage time controls (normal time, or
## 1, 4 or 12 hours a second). Fast time is Simulation's (start_passage):
## the same timeline as always, which stops by itself when something needs
## the captain; the reason is shown here.
##
## Reads GameSession and Simulation every frame; only the buttons change
## anything. Shown underway on voyages of at least LONG_VOYAGE_NM.
##
## Captain's Chartroom: the distance, ETA and progress are in the route panel
## and (I026) the speed and wind on the instruments, so those lines are kept (tests,
## diagnostics) but not shown here; the boat line shows only when the boat
## wants care, and tight stores are shown in the warning colour.

signal chart_requested
signal save_requested

## Voyages at least this long show the panel.
const LONG_VOYAGE_NM := 60.0
const RATE_LABELS := ["1 h/s", "4 h/s", "12 h/s"]

var _title: Label
var _lines := {}
var _progress: ProgressBar
var _normal: Button
var _rate_buttons: Array[Button] = []
var _stopped: Label
var _outlook_key := ""
var _outlook_at := -INF
var _outlook_text := ""


func _ready() -> void:
	name = "PassagePanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(430, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 4)
	add_child(box)
	_title = Label.new()
	_title.name = "Title"
	_title.theme_type_variation = &"HeaderLabel"
	box.add_child(_title)
	for key in ["position", "distance", "wind", "outlook", "stores", "boat"]:
		var label := Label.new()
		label.name = key.capitalize()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override(&"font_size", 17)
		box.add_child(label)
		_lines[key] = label
		label.visible = key not in ["distance", "wind"]
		if key == "distance":
			_progress = ProgressBar.new()
			_progress.name = "Progress"
			_progress.show_percentage = false
			_progress.custom_minimum_size = Vector2(0, 10)
			_progress.visible = false
			box.add_child(_progress)
	_stopped = Label.new()
	_stopped.name = "Stopped"
	_stopped.theme_type_variation = &"MutedLabel"
	_stopped.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stopped.add_theme_font_size_override(&"font_size", 16)
	box.add_child(_stopped)
	var row := HBoxContainer.new()
	row.name = "Speeds"
	row.add_theme_constant_override(&"separation", 4)
	box.add_child(row)
	var group := ButtonGroup.new()
	_normal = _make_button(row, "Normal", "Normal time", "Back to normal time.")
	_normal.toggle_mode = true
	_normal.button_group = group
	_normal.pressed.connect(Simulation.stop_passage)
	for i in Simulation.PASSAGE_RATES.size():
		var rate: float = Simulation.PASSAGE_RATES[i]
		var button := _make_button(row, "Rate%d" % i, RATE_LABELS[i],
			Loc.n("Let %d hour pass every second. Stops by itself when something needs you.", "Let %d hours pass every second. Stops by itself when something needs you.", roundi(rate / 3600.0)) % roundi(rate / 3600.0))
		button.toggle_mode = true
		button.button_group = group
		button.pressed.connect(_on_rate.bind(rate))
		_rate_buttons.append(button)
	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override(&"separation", 4)
	box.add_child(actions)
	_make_button(actions, "Chart", "Chart", "Open the chart (time stops while it is open).").pressed.connect(func() -> void:
		Simulation.stop_passage()
		chart_requested.emit())
	_make_button(actions, "Save", "Save…", "Save the game.").pressed.connect(func() -> void:
		Simulation.stop_passage()
		save_requested.emit())
	Simulation.passage_interrupted.connect(_on_interrupted)
	GameSession.voyage_started.connect(func() -> void: _stopped.text = "")
	refresh()


func _make_button(parent: Control, node_name: String, text: String, tip: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.tooltip_text = tip
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(76, 0)
	parent.add_child(button)
	return button


func _process(_delta: float) -> void:
	visible = should_show()
	if visible:
		refresh()


## Underway on a long voyage (not at anchor).
static func should_show() -> bool:
	return GameSession.is_active() and GameSession.is_underway() and not GameSession.is_anchored() \
		and GameSession.get_voyage_total_nm() >= LONG_VOYAGE_NM


func _on_rate(rate: float) -> void:
	var error := Simulation.start_passage(rate)
	_stopped.text = error if error != "" else ""


func _on_interrupted(_reason: StringName, text: String) -> void:
	_stopped.text = Loc.t("Normal time: %s") % text
	# Fish that nibbled and swam off meanwhile (Iteration 18), said once.
	var nibbles := GameSession.take_quiet_nibbles()
	if nibbles > 0:
		_stopped.text += Loc.t("  (%d fish nibbled and swam off on the way.)") % nibbles


func refresh() -> void:
	if not GameSession.is_underway():
		return
	var catalog := PortCatalog.get_default()
	var voyage := GameSession.get_voyage()
	var destination := catalog.get_display_name(GameSession.get_voyage_destination_id())
	_title.text = Loc.t("Long passage to %s") % destination
	var days_at_sea := (GameSession.get_game_time() - voyage.departed_at) / 86400.0
	_lines.position.text = Loc.t("%s  ·  day %d at sea") % [GeoMath.format_position(GameSession.get_vessel_position()), floori(days_at_sea) + 1]
	var remaining := GameSession.get_voyage_remaining_nm()
	var total := GameSession.get_voyage_total_nm()
	var eta := Simulation.get_eta()
	_lines.distance.text = Loc.t("%s nm to go  ·  ETA about %s") % [_thousands(roundi(remaining)), Simulation.format_game_time(eta)]
	_progress.value = 100.0 * (1.0 - remaining / total) if total > 0.0 else 100.0
	var wind := Simulation.get_wind_at(GameSession.get_vessel_position())
	_lines.wind.text = Loc.format("%.1f kn  ·  %s", [GameSession.get_vessel_speed_kn(), Hud.describe_wind(wind)])
	_lines.outlook.text = _outlook()
	var stores := GameSession.get_provisions().endurance_days()
	var days_left := maxf(eta - GameSession.get_game_time(), 0.0) / 86400.0
	_lines.stores.text = Loc.t("Stores %s  ·  about %s of sailing left%s") % [Provisions.format_days(stores), Provisions.format_days(days_left),
		"" if stores >= days_left + 2.0 else (Loc.t("  ·  tight") if stores >= days_left else Loc.t("  ·  not enough"))]
	var stores_style := &"WarningLabel" if stores < days_left + 2.0 else &""
	if _lines.stores.theme_type_variation != stores_style:
		_lines.stores.theme_type_variation = stores_style
	var care := _care_note()
	_lines.boat.text = Loc.t("Boat: hull %s%s") % [VesselCondition.describe(GameSession.get_condition()), care]
	_lines.boat.visible = care != "" or GameSession.get_condition() <= 60.0
	var running := Simulation.passage_rate
	_normal.set_pressed_no_signal(running <= 0.0)
	for i in _rate_buttons.size():
		_rate_buttons[i].set_pressed_no_signal(is_equal_approx(running, Simulation.PASSAGE_RATES[i]))


## Hazards in the forecast along the route (refreshed every game half hour),
## and an honest note that beyond the forecast nothing is known.
func _outlook() -> String:
	var key := "%d" % GameSession.get_voyage().revision
	if key != _outlook_key or absf(GameSession.get_game_time() - _outlook_at) >= 1800.0:
		_outlook_key = key
		_outlook_at = GameSession.get_game_time()
		var hazards := Simulation.get_hazards_ahead()
		if hazards.is_empty():
			_outlook_text = Loc.t("Outlook: no hazards in the next %d hours") % roundi(Simulation.DISPLAY_HORIZON_HOURS)
		else:
			var first: Dictionary = hazards[0]
			_outlook_text = Loc.t("Outlook: %s in about %d h") % [String(first.label).to_lower(), maxi(roundi(float(first.hours)), 1)]
		_outlook_text += Loc.t("; further on, not yet known.")
	return _outlook_text


## The boat-care areas that want attention ("rigging and sails: service
## recommended"), or nothing when all is well.
func _care_note() -> String:
	var notes := PackedStringArray()
	for area in BoatCare.AREAS:
		var level := GameSession.get_care_level(area)
		if level == BoatCare.LEVEL_RECOMMENDED or level == BoatCare.LEVEL_NEEDED:
			notes.append("%s: %s" % [Loc.t(BoatCare.AREA_NAMES[area]).to_lower(), Loc.t(BoatCare.LEVEL_NAMES[level]).to_lower()])
	return "  ·  " + ", ".join(notes) if not notes.is_empty() else ""


static func _thousands(value: int) -> String:
	var text := str(absi(value))
	var out := ""
	while text.length() > 3:
		out = "," + text.substr(text.length() - 3) + out
		text = text.substr(0, text.length() - 3)
	return ("-" if value < 0 else "") + text + out


func get_line(key: String) -> String:
	return (_lines[key] as Label).text if _lines.has(key) else ""


func get_stopped_text() -> String:
	return _stopped.text
