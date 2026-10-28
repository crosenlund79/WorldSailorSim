class_name HarbourOfficeMenu
extends SimplePanel
## The harbour office on the quay (I026 stage 02): the harbour's tier and
## services, the opening hours of every business on the quay, a few words
## about the place and the forecast in words (HarbourNotes).
##
## After hours its hatch is open (`hatch`): the same information, and the
## essentials that cannot wait for the morning - food and water for the boat
## (where the harbour has a grocery store; GameSession.buy_provisions, the
## everyday stores) and an emergency repair of a damaged hull (where it has a
## boatyard; the yard's own repair, priced and timed as always, the time
## passing ashore through App). Nobody is stranded by the clock.

signal repair_requested

## Hull condition (%) below which the hatch offers an emergency repair.
const DAMAGED_BELOW := 70.0

var hatch := false
var layout: QuayLayout
var _food: Button
var _repair: Button
var _essentials: Label


func _ready() -> void:
	var place := GameSession.get_location()
	var port_id := GameSession.get_location_id()
	if layout == null:
		layout = QuayLayout.build(port_id)
	var title := Loc.t("After-hours hatch") if hatch else Loc.t("Harbour Office")
	_build(title + (" · %s" % place.display_name if place else ""), 760.0)
	if hatch:
		_label("HatchNote", Loc.t("The office is closed for the day; the hatch is open for what cannot wait until morning."), &"MutedLabel")
	_label("ServicesLine", HarbourNotes.services(port_id))
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.custom_minimum_size = Vector2(720, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override(&"separation", 6)
	scroll.add_child(column)
	_section(column, "HoursList", Loc.t("Opening hours (local time)"), HarbourNotes.hours_lines(layout, GameSession.get_game_time()))
	_section(column, "ForecastList", Loc.t("The forecast"), HarbourNotes.forecast_lines(port_id, GameSession.get_game_time()))
	var notes := HarbourNotes.local_notes(port_id)
	if not notes.is_empty():
		_section(column, "AboutList", Loc.t("About the harbour"), notes)
	if hatch:
		_essentials = _label("EssentialsNote", "", &"MutedLabel")
		var row := HBoxContainer.new()
		row.name = "EssentialsRow"
		row.add_theme_constant_override(&"separation", 12)
		_box.add_child(row)
		_food = Button.new()
		_food.name = "FoodButton"
		_food.custom_minimum_size = Vector2(320, 0)
		_food.pressed.connect(_on_food)
		row.add_child(_food)
		_repair = Button.new()
		_repair.name = "RepairButton"
		_repair.custom_minimum_size = Vector2(320, 0)
		_repair.pressed.connect(func() -> void: repair_requested.emit())
		row.add_child(_repair)
		GameSession.funds_changed.connect(func(_f: int) -> void: refresh())
	_button("CloseButton", "Close", close)
	refresh()


func _section(column: VBoxContainer, node_name: String, heading: String, lines: Array[String]) -> void:
	var head := Label.new()
	head.name = node_name + "Heading"
	head.text = heading
	head.theme_type_variation = &"HeaderLabel"
	column.add_child(head)
	var body := Label.new()
	body.name = node_name
	body.text = "\n".join(lines)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(690, 0)
	column.add_child(body)


func refresh() -> void:
	if not hatch or _food == null:
		return
	var grocery := GameSession.has_facility(HarbourFacilities.GROCERY)
	var price := GameSession.get_provisions_price()
	_food.visible = grocery
	_food.disabled = price <= 0 or price > GameSession.get_funds()
	_food.text = Loc.t("Food and water (%s)") % GameSession.format_money(price) if price > 0 else Loc.t("Food and water are full")
	var yard := GameSession.has_facility(HarbourFacilities.BOATYARD)
	var damaged := GameSession.get_condition() < DAMAGED_BELOW
	_repair.visible = yard
	var quote := GameSession.service_quote(BoatCare.SERVICE_REPAIR)
	_repair.disabled = not damaged or GameSession.service_refusal(BoatCare.SERVICE_REPAIR) != ""
	_repair.text = Loc.t("Emergency hull repair (%s)") % GameSession.format_money(int(quote.cost)) if damaged else Loc.t("The hull needs no emergency repair")
	var lines: Array[String] = []
	if not grocery:
		lines.append(Loc.t("There is no grocery store here."))
	if not yard:
		lines.append(Loc.t("There is no boatyard here."))
	_essentials.text = " ".join(lines) if not lines.is_empty() else Loc.t("Everything else opens again in the morning.")


func _on_food() -> void:
	var error := GameSession.buy_provisions()
	notify(error if not error.is_empty() else Loc.t("Food and water for %d days are brought down to the boat. Funds: %s.") % [
		roundi(Provisions.CAPACITY_DAYS), GameSession.format_money(GameSession.get_funds())])
	refresh()


func get_food_button() -> Button:
	return _food


func get_repair_button() -> Button:
	return _repair


func focus_default() -> void:
	(_buttons.get_node(^"CloseButton") as Button).grab_focus()
