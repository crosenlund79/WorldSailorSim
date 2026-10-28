class_name CafeMenu
extends SimplePanel
## The café on the quay (I026 stage 02): order a coffee for a small price and
## sit at a terrace table with it. The money goes through GameSession
## (buy_cafe_coffee); App seats the Captain (HarbourFront.sit_at_cafe).
## Nothing to earn: no achievement, no energy, just a coffee by the water.

signal order_requested

var _info: Label
var _funds: Label
var _order: Button


func _ready() -> void:
	var place := GameSession.get_location()
	_build(Loc.t("Café") + (" · %s" % place.display_name if place else ""), 600.0)
	_info = _label("Info", Loc.t("A small café on the quay. A coffee is %s; take it to a table on the terrace and watch the harbour for a while.") %
		GameSession.format_money(GameSession.cafe_coffee_price()), &"MutedLabel")
	_funds = _label("Funds", "", &"MutedLabel")
	_button("CloseButton", "Close", close)
	_order = _button("OrderButton", "", func() -> void: order_requested.emit(), 300.0)
	refresh()


func refresh() -> void:
	var price := GameSession.cafe_coffee_price()
	_funds.text = Loc.t("Funds: %s") % GameSession.format_money(GameSession.get_funds())
	_order.text = Loc.t("Order a coffee and sit outside (%s)") % GameSession.format_money(price)
	_order.disabled = price > GameSession.get_funds()


func get_order_button() -> Button:
	return _order


func focus_default() -> void:
	if _order and not _order.disabled:
		_order.grab_focus()
	else:
		(_buttons.get_node(^"CloseButton") as Button).grab_focus()
