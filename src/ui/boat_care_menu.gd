class_name BoatCareMenu
extends SimplePanel
## Boat care at the boatyard (Iteration 14), opened from the boatyard panel.
##
## The boat's condition at a glance (BoatCareView), then only the work this
## yard can do: repairs and the rig and engine services at any boatyard, the
## haul-out only where the yard can lift boats out. Each shows its price and
## how long it takes; a service that is not needed, or not affordable, says
## why instead. Below, the equipment that can be fitted here.
##
## GameSession does every change (one transaction each); the App spends the
## time the work takes ashore (`time_requested`) and opens the haul-out
## (`haul_out_requested`).

signal time_requested(minutes: float)
signal haul_out_requested

const PANEL_WIDTH := 1000.0
const BODY_SIZE := Vector2(960, 560)

var _view: BoatCareView
var _header: Label
var _services := {}
var _upgrades := {}
var _magic: Button
var _haul_out: Button


func _ready() -> void:
	_build("Boat care", PANEL_WIDTH)
	_header = _label("Header", "", &"MutedLabel")
	var scroll := ScrollContainer.new()
	scroll.name = "Body"
	scroll.custom_minimum_size = BODY_SIZE
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", 12)
	scroll.add_child(body)
	_view = BoatCareView.new()
	_view.name = "Overview"
	body.add_child(_view)
	body.add_child(HSeparator.new())
	body.add_child(_heading(Loc.t("At this boatyard")))
	var services := GridContainer.new()
	services.name = "Services"
	services.columns = 3
	services.add_theme_constant_override(&"h_separation", 16)
	services.add_theme_constant_override(&"v_separation", 8)
	body.add_child(services)
	for service in [BoatCare.SERVICE_REPAIR, BoatCare.SERVICE_RIG, BoatCare.SERVICE_ENGINE]:
		_add_service_row(services, service)
	if GameSession.has_facility(HarbourFacilities.HAUL_OUT):
		var name := _cell(BoatCare.SERVICE_NAMES[BoatCare.SERVICE_HAUL_OUT], 260.0)
		var note := _cell("", 380.0, &"MutedLabel")
		_haul_out = Button.new()
		_haul_out.name = "HaulOutButton"
		_haul_out.custom_minimum_size = Vector2(230, 0)
		_haul_out.pressed.connect(haul_out_requested.emit)
		services.add_child(name)
		services.add_child(note)
		services.add_child(_haul_out)
		_services[BoatCare.SERVICE_HAUL_OUT] = [note, _haul_out]
	body.add_child(HSeparator.new())
	body.add_child(_heading("Equipment"))
	var equipment := GridContainer.new()
	equipment.name = "Equipment"
	equipment.columns = 3
	equipment.add_theme_constant_override(&"h_separation", 16)
	equipment.add_theme_constant_override(&"v_separation", 10)
	body.add_child(equipment)
	for upgrade in BoatCare.get_upgrades():
		# Gear sold over the counter is the chandlery's (I020); the yard fits
		# what needs a yard.
		if HarbourTrades.is_chandlery_upgrade(String(upgrade.id)):
			continue
		# Only what this yard can fit: the coating needs a haul-out yard.
		var needs_haul_out: bool = upgrade.get("yard", "boatyard") == "haul_out"
		if needs_haul_out and not GameSession.has_facility(HarbourFacilities.HAUL_OUT) and not GameSession.has_upgrade(upgrade.id):
			continue
		_add_upgrade_row(equipment, upgrade)
	_add_magic_anchor_row(equipment)
	_button("CloseButton", "Close", close)
	GameSession.boat_care_changed.connect(refresh)
	GameSession.funds_changed.connect(_on_funds_changed)
	refresh()


func _add_service_row(grid: GridContainer, service: StringName) -> void:
	var button := Button.new()
	button.name = "%sButton" % String(service).to_pascal_case()
	button.custom_minimum_size = Vector2(230, 0)
	button.pressed.connect(_on_service.bind(service))
	var note := _cell("", 380.0, &"MutedLabel")
	grid.add_child(_cell(BoatCare.SERVICE_NAMES[service], 260.0))
	grid.add_child(note)
	grid.add_child(button)
	_services[service] = [note, button]


func _add_upgrade_row(grid: GridContainer, upgrade: Dictionary) -> void:
	var title := _cell(String(upgrade.name), 260.0, &"HeaderLabel")
	var text := _cell(String(upgrade.text), 380.0, &"MutedLabel")
	var button := Button.new()
	button.name = "Fit_%s" % upgrade.id
	button.custom_minimum_size = Vector2(230, 0)
	button.pressed.connect(_on_upgrade.bind(String(upgrade.id)))
	grid.add_child(title)
	grid.add_child(text)
	grid.add_child(button)
	_upgrades[String(upgrade.id)] = button


## The Magic Anchor (0.105b): sold at the chandlery since I020 (before, a
## free prototype here); shown here so the yard's list stays complete.
func _add_magic_anchor_row(grid: GridContainer) -> void:
	var title := _cell("%s\n(%s)" % [GameSession.MAGIC_ANCHOR_NAME, GameSession.MAGIC_ANCHOR_LONG_NAME], 260.0, &"HeaderLabel")
	var text := _cell(Loc.t(GameSession.MAGIC_ANCHOR_TEXT) + " " + Loc.t("Sold at the chandlery, next to the yard."), 380.0, &"MutedLabel")
	_magic = Button.new()
	_magic.name = "Fit_magic_anchor"
	_magic.custom_minimum_size = Vector2(230, 0)
	_magic.disabled = true
	grid.add_child(title)
	grid.add_child(text)
	grid.add_child(_magic)


func get_magic_anchor_button() -> Button:
	return _magic


func refresh() -> void:
	if not is_inside_tree():
		return
	if _magic:
		_magic.text = "Aboard" if GameSession.has_magic_anchor() else "At the chandlery"
		_magic.disabled = true
	var facilities := GameSession.get_harbour_facilities()
	var location := GameSession.get_location()
	_header.text = Loc.t("The %s in %s · %s%s · %s available") % [GameSession.get_vessel_definition().display_name,
		location.display_name if location else "harbour", Loc.t(HarbourFacilities.TIER_NAMES[facilities.get_tier()]),
		Loc.t(" (this yard can haul boats out)") if facilities.has(HarbourFacilities.HAUL_OUT) else "",
		GameSession.format_money(GameSession.get_funds())]
	_view.refresh()
	for service: StringName in _services:
		var note := _services[service][0] as Label
		var button := _services[service][1] as Button
		var quote := GameSession.service_quote(service)
		var refusal := GameSession.service_refusal(service)
		if service == BoatCare.SERVICE_HAUL_OUT:
			note.text = "Out of the water for a day: the bottom scrubbed, the hull seen to. Other work can be done while she is out."
			button.text = Loc.t("Haul out… (from %s)") % GameSession.format_money(int(quote.cost))
			button.disabled = refusal != ""
			button.tooltip_text = refusal
			continue
		note.text = refusal if refusal != "" else Loc.t("%s · about %s") % [GameSession.format_money(int(quote.cost)), _duration(float(quote.minutes))]
		button.text = "Have it done" if refusal == "" else "Not needed" if not refusal.begins_with("Not enough") else Loc.t("Too expensive")
		button.disabled = refusal != ""
	for id: String in _upgrades:
		var button := _upgrades[id] as Button
		if GameSession.has_upgrade(id):
			button.text = "Fitted"
			button.disabled = true
			continue
		var refusal := GameSession.upgrade_refusal(id)
		button.text = Loc.t("Fit it (%s)") % GameSession.format_money(GameSession.upgrade_price(id))
		button.disabled = refusal != ""
		button.tooltip_text = refusal


func _on_funds_changed(_funds: int) -> void:
	refresh()


func _on_service(service: StringName) -> void:
	var result := GameSession.perform_service(service)
	if result.error != "":
		notify(result.error)
		return
	time_requested.emit(float(result.minutes))
	SessionLog.write("boat_service", {"service": String(service), "cost": result.cost, "minutes": result.minutes,
		"port": String(GameSession.get_location_id())})
	notify(Loc.t("%s done: %s, %s.") % [BoatCare.SERVICE_NAMES[service], GameSession.format_money(int(result.cost)), _duration(float(result.minutes))])
	refresh()


func _on_upgrade(id: String) -> void:
	var result := GameSession.install_upgrade(id)
	if result.error != "":
		notify(result.error)
		return
	time_requested.emit(float(result.minutes))
	SessionLog.write("upgrade_fitted", {"upgrade": id, "cost": result.cost, "port": String(GameSession.get_location_id())})
	notify(Loc.t("%s fitted for %s.") % [Loc.t(String(BoatCare.get_upgrade(id).name)), GameSession.format_money(int(result.cost))])
	refresh()


func get_service_button(service: StringName) -> Button:
	return _services[service][1] if _services.has(service) else null


func get_upgrade_button(id: String) -> Button:
	return _upgrades.get(id)


func get_overview() -> BoatCareView:
	return _view


func focus_default() -> void:
	(_box.find_child("CloseButton", true, false) as Button).grab_focus()


static func _duration(minutes: float) -> String:
	if minutes >= 24.0 * 60.0:
		return Loc.n("%d day", "%d days", roundi(minutes / 1440.0)) % roundi(minutes / 1440.0)
	if minutes >= 90.0:
		return Loc.t("%s hours") % (str(roundi(minutes / 60.0)) if fmod(minutes, 60.0) < 15.0 or fmod(minutes, 60.0) > 45.0 else "%.1f" % (minutes / 60.0))
	return Loc.t("%d minutes") % roundi(minutes)


static func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"HeaderLabel"
	return label


static func _cell(text: String, width: float, variation: StringName = &"") -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(width, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL if width > 300.0 else Control.SIZE_FILL
	return label
