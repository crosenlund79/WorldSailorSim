class_name DevTestPanel
extends ModalPanel
## The development-only test panel (DevTools): buttons for test weather,
## boat condition, rescue, provisions and time, and (I027 playtest) money,
## fuel, lures, a rare bite, dock animals, harbour hours, a short passage and
## dreams, with the live state shown so
## each test can be checked at a glance. Opened with F10 or from the pause
## menu, only where DevTools.is_enabled(). Clearly marked as a developer tool.
## The game is paused while it is open; "Advance" buttons move time through
## the normal simulation.

var _status: Label
var _buttons := {}
var _rows: Array[Control] = []


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.09, 0.12, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(980, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	_add_label(box, "DEVELOPER TEST TOOLS", &"HeaderLabel")
	_add_label(box, "Not part of the game: shown only when running from the Godot editor (debug). Everything here acts " +
		"on the real simulation. Test weather is never saved and is removed on New Game, Load and Main menu.", &"MutedLabel")
	_status = _add_label(box, "", &"")
	_status.name = "Status"
	_status.custom_minimum_size = Vector2(920, 0)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_row(box, "Weather", [
		["NormalWeather", "Normal weather", func() -> void: DevTools.restore_normal_weather()],
		["Gale", "Strong winds (gale)", _scenario.bind(DevTools.SCENARIO_GALE)],
		["Storm", "Severe storm", _scenario.bind(DevTools.SCENARIO_STORM)],
		["Squall", "Thunderstorm / squall", _scenario.bind(DevTools.SCENARIO_SQUALL)],
		["StormAhead", "Storm ahead on course", _scenario.bind(DevTools.SCENARIO_STORM_AHEAD)],
	])
	var condition_buttons := []
	for percent in DevTools.CONDITION_PRESETS:
		condition_buttons.append(["Condition%d" % percent, "%d %%" % percent, DevTools.set_condition.bind(percent)])
	_row(box, "Condition", condition_buttons)
	_row(box, "Rescue", [
		["RescueTest", "Rescue test: 1 % + storm (at sea)", func() -> void: _report(DevTools.prepare_rescue(),
			"Rescue test ready: close this panel and let time run (at most 5 game minutes).")],
	])
	_row(box, "Provisions", [
		["Stores3", "3 days (low)", DevTools.set_provisions.bind(3.0)],
		["Stores05", "0.5 day (critical)", DevTools.set_provisions.bind(0.5)],
		["Stores0", "Empty", DevTools.set_provisions.bind(0.0)],
		["Stores14", "Full (test)", DevTools.set_provisions.bind(Provisions.CAPACITY_DAYS)],
	])
	_row(box, "Time", [
		["Advance1", "Advance 1 h", func() -> void: DevTools.advance_hours(1.0)],
		["Advance6", "Advance 6 h", func() -> void: DevTools.advance_hours(6.0)],
		["Advance24", "Advance 24 h", func() -> void: DevTools.advance_hours(24.0)],
	])
	# I027 playtest: more test shortcuts, on the game's own systems.
	_row(box, "Money", [
		["Money1k", "+ €1,000", DevTools.add_money.bind(1000)],
		["Money10k", "+ €10,000", DevTools.add_money.bind(10000)],
	])
	_row(box, "Fuel", [
		["FuelFull", "Full tank", DevTools.set_fuel.bind(1.0)],
		["FuelQuarter", "A quarter", DevTools.set_fuel.bind(0.25)],
		["FuelEmpty", "Empty", DevTools.set_fuel.bind(0.0)],
	])
	_row(box, "Fishing", [
		["Lures", "+5 of every lure", DevTools.add_lures.bind(5)],
		["RareBite", "Rare Gold fish on the line", func() -> void: _report(DevTools.rare_bite(), "A rare fish is on the line.")],
	])
	_row(box, "Pets", [
		["DockCat", "Cat on the dock", func() -> void: _report(DevTools.dock_animal(CompanionState.KIND_CAT), "A cat waits on the pontoon.")],
		["DockDog", "Pug on the dock", func() -> void: _report(DevTools.dock_animal(CompanionState.KIND_DOG), "A Pug waits on the pontoon.")],
		["DockParrot", "Conure on the dock", func() -> void: _report(DevTools.dock_animal(CompanionState.KIND_PARROT), "A conure waits on the pontoon.")],
	])
	_row(box, "Harbour", [
		["To07", "To 07:00", DevTools.advance_to_local_hour.bind(7.0)],
		["To10", "To 10:00 (shops open)", DevTools.advance_to_local_hour.bind(10.0)],
		["To20", "To 20:00 (evening)", DevTools.advance_to_local_hour.bind(20.0)],
	])
	_row(box, "Passage", [
		["PlanShort", "Plan a short passage", func() -> void: _report(DevTools.plan_short_passage(), "Course plotted: set sail from the helm.")],
		["Dream", "Fulfil the next dream", func() -> void: _report(DevTools.fulfil_dream(), "A dream came true.")],
	])
	# The rows scroll when the screen (or a 130 % interface) is too short for them.
	FitScroll.wrap(_rows, panel)
	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "Close (F10 / Esc)"
	close_button.pressed.connect(close)
	box.add_child(close_button)
	_buttons["CloseButton"] = close_button
	refresh()


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		refresh()


func refresh() -> void:
	if not GameSession.is_active():
		_status.text = "No game running."
		return
	var provisions := GameSession.get_provisions()
	var scenario := DevTools.SCENARIO_NAMES.get(DevTools.scenario, "none (ordinary weather)") as String
	_status.text = ("Test weather: %s%s\nAt the boat: %s\nBoat: %s, hull %s  ·  Funds %s  ·  Rescues %d\n" +
		"Food %s  ·  Water %s  ·  Endurance %s\nTime: %s  ·  %s") % [
		scenario, "  (active; use Normal weather to remove)" if DevTools.is_scenario_active() else "",
		DevTools.describe_weather_here(), GameSession.get_vessel_definition().display_name,
		VesselCondition.describe(GameSession.get_condition()), GameSession.format_money(GameSession.get_funds()),
		GameSession.get_rescue_count(), Provisions.format_days(provisions.food_days),
		Provisions.format_days(provisions.water_days), Provisions.format_days(provisions.endurance_days()),
		Simulation.format_game_time(GameSession.get_game_time()),
		"underway" if GameSession.is_underway() else "in harbour"]


func get_button(button_name: String) -> Button:
	return _buttons.get(button_name) as Button


func focus_default() -> void:
	(_buttons["CloseButton"] as Button).grab_focus()


func _scenario(id: StringName) -> void:
	_report(DevTools.activate_scenario(id), "Test weather: %s." % DevTools.SCENARIO_NAMES[id])


func _report(error: String, success: String) -> void:
	notify(error if not error.is_empty() else success)
	refresh()


func _row(box: VBoxContainer, title: String, buttons: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = title
	label.custom_minimum_size = Vector2(110, 0)
	label.theme_type_variation = &"MutedLabel"
	row.add_child(label)
	for spec: Array in buttons:
		var button := Button.new()
		button.name = spec[0]
		button.text = spec[1]
		button.pressed.connect(spec[2])
		button.pressed.connect(refresh)
		row.add_child(button)
		_buttons[spec[0]] = button
	box.add_child(row)
	_rows.append(row)


static func _add_label(box: Container, text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(920, 0)
	box.add_child(label)
	return label
