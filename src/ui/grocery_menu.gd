class_name GroceryMenu
extends SimplePanel
## The harbour grocery store: fill food and water up to 14 days each, paying
## GameSession.PROVISIONS_PRICE_PER_DAY per missing day (food and water
## counted together). One purchase fills both; it is refused when the money
## is not enough. Every harbour has one (the pontoon's grocery station, or the
## provisions panel and the boatyard).
##
## Its counter also sells a replacement captain's hat (Visual Identity V01),
## in its own row with its own price, so the provisions figures above are
## exactly as before.
##
## Iteration 16: "Stock up for a long passage" fills both beyond the everyday
## 14 days, up to what this boat can stow (its passage stores).

## The fishmonger next door (I020): App opens it on top.
signal fishmonger_requested

var _stores: Label
var _price: Label
var _note: Label
var _buy: Button
var _stock_up: Button
var _stock_note: Label
var _hat_info: Label
var _buy_hat: Button
## Fishing tackle and the catch (Iteration 13).
var _tackle: OptionButton
var _buy_lure: Button
var _catch_info: Label
var _sell_catch: Button


func _ready() -> void:
	var place := GameSession.get_location()
	_build(Loc.t("Grocery store") + (" · %s" % place.display_name if place else ""))
	_label("Info", Loc.t("Fresh food and water, filled up to %d days each. %s per missing day of food or of water.") % [
		roundi(Provisions.CAPACITY_DAYS), GameSession.format_money(GameSession.PROVISIONS_PRICE_PER_DAY)], &"MutedLabel")
	_stores = _label("Stores", "")
	_price = _label("Price", "", &"HeaderLabel")
	_note = _label("Note", "")
	var stock_row := HBoxContainer.new()
	stock_row.name = "StockUpRow"
	stock_row.add_theme_constant_override("separation", 14)
	_box.add_child(stock_row)
	_stock_note = Label.new()
	_stock_note.name = "StockUpNote"
	_stock_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stock_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stock_note.custom_minimum_size = Vector2(300, 0)
	stock_row.add_child(_stock_note)
	_stock_up = Button.new()
	_stock_up.name = "StockUpButton"
	_stock_up.custom_minimum_size = Vector2(240, 0)
	_stock_up.pressed.connect(_on_stock_up)
	stock_row.add_child(_stock_up)
	_box.add_child(HSeparator.new())
	var hat_row := HBoxContainer.new()
	hat_row.name = "HatRow"
	hat_row.add_theme_constant_override("separation", 14)
	_box.add_child(hat_row)
	_hat_info = Label.new()
	_hat_info.name = "HatInfo"
	_hat_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hat_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hat_info.custom_minimum_size = Vector2(300, 0)
	hat_row.add_child(_hat_info)
	_buy_hat = Button.new()
	_buy_hat.name = "BuyHatButton"
	_buy_hat.custom_minimum_size = Vector2(240, 0)
	_buy_hat.pressed.connect(_on_buy_hat)
	hat_row.add_child(_buy_hat)
	_build_tackle()
	_button("CloseButton", "Close", close)
	_buy = _button("BuyButton", "Buy", _on_buy, 240.0)
	# Selling the catch at the fishmonger (opened on top of this menu) changes
	# the funds and the catch shown here.
	GameSession.funds_changed.connect(_on_funds_changed)
	GameSession.fishing_changed.connect(refresh)
	refresh()


## Lures for the rod, and buying the catch in the cool box (Iteration 13).
func _build_tackle() -> void:
	var row := HBoxContainer.new()
	row.name = "TackleRow"
	row.add_theme_constant_override("separation", 14)
	_box.add_child(row)
	var label := Label.new()
	label.text = "Fishing lures"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	_tackle = OptionButton.new()
	_tackle.name = "Tackle"
	_tackle.custom_minimum_size = Vector2(240, 0)
	for lure in FishingCatalog.get_default().lures:
		_tackle.add_item("%s (%s)" % [Loc.t(String(lure.name)), GameSession.format_money(int(lure.price))])
	row.add_child(_tackle)
	_buy_lure = Button.new()
	_buy_lure.name = "BuyLureButton"
	_buy_lure.text = "Buy lure"
	_buy_lure.custom_minimum_size = Vector2(150, 0)
	_buy_lure.pressed.connect(_on_buy_lure)
	row.add_child(_buy_lure)
	var catch_row := HBoxContainer.new()
	catch_row.name = "CatchRow"
	catch_row.add_theme_constant_override("separation", 14)
	_box.add_child(catch_row)
	_catch_info = Label.new()
	_catch_info.name = "CatchInfo"
	_catch_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_catch_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_catch_info.custom_minimum_size = Vector2(300, 0)
	catch_row.add_child(_catch_info)
	# I020: the catch is sold at the fishmonger next door (one place, one
	# transaction for selling fish).
	_sell_catch = Button.new()
	_sell_catch.name = "FishmongerButton"
	_sell_catch.custom_minimum_size = Vector2(240, 0)
	_sell_catch.pressed.connect(fishmonger_requested.emit)
	catch_row.add_child(_sell_catch)


func _on_funds_changed(_funds: int) -> void:
	refresh()


func refresh() -> void:
	var provisions := GameSession.get_provisions()
	var price := GameSession.get_provisions_price()
	var funds := GameSession.get_funds()
	_stores.text = Loc.format("Aboard: food %s, water %s. Missing: %.1f days in all.", [Provisions.format_days(provisions.food_days),
		Provisions.format_days(provisions.water_days), GameSession.get_missing_provision_days()])
	_price.text = Loc.t("Price %s  ·  Funds %s") % [GameSession.format_money(price), GameSession.format_money(funds)]
	if price > 0 and price <= funds:
		_price.text += " → %s" % GameSession.format_money(funds - price)
	_buy.text = Loc.t("Buy for %s") % GameSession.format_money(price)
	var harbour := GameSession.is_moored_in_harbour()
	_buy.disabled = not harbour or provisions.is_full() or price > funds
	if not harbour:
		_note.text = "The grocery store is in harbour; you are at sea."
	elif provisions.is_full():
		_note.text = "Food and water are already full."
	elif price > funds:
		_note.text = Loc.t("Not enough money: you need %s. Remote work at the boat's work station earns %s an hour.") % [
			GameSession.format_money(price), GameSession.format_money(GameSession.REMOTE_WORK_PAY_PER_HOUR)]
	else:
		_note.text = Loc.t("Food and water will be full (%d days each).") % roundi(Provisions.CAPACITY_DAYS)
	_refresh_stock_up(harbour, funds)
	_refresh_hat(harbour, funds)
	_refresh_tackle(harbour)


## Passage stores (Iteration 16): up to what this boat can stow.
func _refresh_stock_up(harbour: bool, funds: int) -> void:
	var days := GameSession.get_passage_store_days()
	var price := GameSession.get_provisions_price(days)
	var full := GameSession.get_provisions().is_full(days)
	_stock_up.text = Loc.t("Stock up (%s)") % GameSession.format_money(price)
	_stock_up.disabled = not harbour or full or price > funds
	var vessel := GameSession.get_vessel_definition().display_name
	if full:
		_stock_note.text = Loc.t("Long passage: the %s is stocked for %d days, all she can stow.") % [vessel, roundi(days)]
	else:
		_stock_note.text = Loc.t("Long passage: stow food and water for %d days each, all the %s can carry.") % [roundi(days), vessel]


func _refresh_tackle(harbour: bool) -> void:
	var catalog := FishingCatalog.get_default()
	var fishing := GameSession.get_fishing()
	_buy_lure.disabled = not harbour
	var total := 0
	for fish in fishing.hold:
		total += catalog.price(fish.species, float(fish.kg))
	_catch_info.text = Loc.t("Your catch: %d fish in the cool box.") % fishing.hold.size() if not fishing.hold.is_empty() \
		else Loc.t("Your catch: the cool box is empty.")
	_sell_catch.text = Loc.t("To the fishmonger (%s)…") % GameSession.format_money(total)
	_sell_catch.disabled = not harbour or not GameSession.has_facility(HarbourFacilities.FISHMONGER)


func _on_buy_lure() -> void:
	var lure: Dictionary = FishingCatalog.get_default().lures[maxi(_tackle.selected, 0)]
	var error := GameSession.buy_lure(lure.id)
	notify(error if not error.is_empty() else Loc.t("Bought a %s. You have %d.") % [String(lure.name).to_lower(), GameSession.get_fishing().get_lure_count(lure.id)])
	refresh()


func _refresh_hat(harbour: bool, funds: int) -> void:
	var price := GameSession.get_hat_price()
	var owned := GameSession.get_hat().is_owned()
	_buy_hat.text = Loc.t("Buy captain's hat (%s)") % GameSession.format_money(price)
	_buy_hat.disabled = not harbour or owned or price > funds
	if owned:
		_hat_info.text = "Captain's hats: you already have yours."
	elif price > funds:
		_hat_info.text = Loc.t("Captain's hats, %s. Not enough money right now.") % GameSession.format_money(price)
	else:
		_hat_info.text = Loc.t("A replacement captain's hat, %s. Hold onto this one.") % GameSession.format_money(price)


func get_buy_button() -> Button:
	return _buy


func get_buy_hat_button() -> Button:
	return _buy_hat


func _on_buy_hat() -> void:
	var price := GameSession.get_hat_price()
	var error := GameSession.buy_hat()
	notify(error if not error.is_empty() else Loc.t("Bought a new captain's hat for %s. Press H to put it on.") % GameSession.format_money(price))
	refresh()


func _on_buy() -> void:
	var price := GameSession.get_provisions_price()
	var error := GameSession.buy_provisions()
	notify(error if not error.is_empty() else Loc.t("Bought food and water for %s. Stores full: %s each.") % [
		GameSession.format_money(price), Provisions.format_days(Provisions.CAPACITY_DAYS)])
	refresh()


func get_stock_up_button() -> Button:
	return _stock_up


func _on_stock_up() -> void:
	var days := GameSession.get_passage_store_days()
	var price := GameSession.get_provisions_price(days)
	var error := GameSession.buy_provisions(days)
	notify(error if not error.is_empty() else Loc.t("Stocked up for a long passage for %s: %s of food and water.") % [
		GameSession.format_money(price), Provisions.format_days(days)])
	refresh()


func focus_default() -> void:
	if _buy.disabled:
		(find_child("CloseButton", true, false) as Button).grab_focus()
	else:
		_buy.grab_focus()
