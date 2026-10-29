class_name FuelMenu
extends SimplePanel
## The fuel berth's pump on the quay (I027, The Cost of the Wind): how much is
## in the boat's tank and how far it goes under engine, the price here, and
## filling up or adding a little - as much as the money allows. A card pump:
## open at any hour, in every harbour (nobody waits for fuel). The money and
## the tank change through GameSession.buy_fuel only.

const TOP_UP_LITRES := 10.0

var _tank: Label
var _price: Label
var _fill: Button
var _add: Button


func _ready() -> void:
	var place := GameSession.get_location()
	_build(Loc.t("Fuel berth") + (" · %s" % place.display_name if place else ""), 600.0)
	_tank = _label(&"Tank", "")
	_price = _label(&"Price", "", &"MutedLabel")
	_fill = _button("FillButton", "", func() -> void: _buy(-1.0))
	_add = _button("AddButton", "", func() -> void: _buy(TOP_UP_LITRES))
	_button("CloseButton", Loc.t("Close"), close)
	GameSession.fuel_changed.connect(refresh)
	refresh()


func refresh() -> void:
	if not is_inside_tree():
		return
	var litres := GameSession.get_fuel_l()
	var tank := GameSession.get_fuel_tank_l()
	_tank.text = Loc.t("In the tank: %d of %d litres  ·  about %d nm under engine") % [roundi(litres), roundi(tank), roundi(GameSession.get_fuel_range_nm())]
	var per_litre := GameSession.get_fuel_price()
	_price.text = Loc.t("Fuel here: %s a litre. Your funds: %s.") % [Loc.format("€%.2f", per_litre), GameSession.format_money(GameSession.get_funds())]
	var space := tank - litres
	_fill.text = Loc.t("Fill up: %d litres (%s)") % [ceili(space), GameSession.format_money(ceili(space * per_litre))]
	_fill.disabled = space < 0.05 or GameSession.get_funds() < 1
	_add.text = Loc.t("Add %d litres (%s)") % [roundi(minf(TOP_UP_LITRES, space)), GameSession.format_money(ceili(minf(TOP_UP_LITRES, space) * per_litre))]
	_add.disabled = space < 0.05 or GameSession.get_funds() < 1


func _buy(litres: float) -> void:
	var result := GameSession.buy_fuel(litres)
	if result.error != "":
		notify(result.error)
	else:
		notify(Loc.t("%d litres of fuel for %s. The tank holds %d litres now.") % [roundi(float(result.litres)),
			GameSession.format_money(int(result.price)), roundi(GameSession.get_fuel_l())])
	refresh()


func focus_default() -> void:
	(_fill if not _fill.disabled else find_child("CloseButton", true, false) as Button).grab_focus()
