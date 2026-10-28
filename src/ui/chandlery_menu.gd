class_name ChandleryMenu
extends TradePanel
## The chandlery (I020): a small shop of things that already mean something
## aboard. Gear for the boat (the boat-care catalogue's own upgrades, fitted
## the same way, once per boat), the Magic Anchor (once, for every boat),
## lures (the fishing catalogue's), and a few things for the cabin (once;
## the Captain's own, to show on any boat with "Make it home").
## I026: Electronics, the instrument packages (InstrumentPackage), bought
## once and fitted to the boat aboard; an owned package is fitted again here
## (or in the instruments' focused view) for nothing.
## Every purchase is whole or nothing, never more than the Captain has.

signal time_requested(minutes: float)


func _ready() -> void:
	_build_trade("Chandlery", "Rope, shackles, lamp oil and good advice. What you buy here is yours at once.")
	_heading("BoatHeading", "For the boat")
	for id: String in HarbourTrades.get_chandlery_upgrades():
		var upgrade := BoatCare.get_upgrade(id)
		_row(id, Loc.t(String(upgrade.name)), Loc.t(String(upgrade.text)), _fit.bind(id))
	_row("magic_anchor", "Magic Anchor",
		"A clever anchor for deep water, where an ordinary one cannot reach the bottom. For every boat you sail.", _buy_magic)
	_add_electronics()
	_heading("FishingHeading", "Fishing tackle")
	for lure: Dictionary in FishingCatalog.get_default().lures:
		_row("lure_%s" % lure.id, Loc.t(String(lure.name)), Loc.t(String(lure.text)), _buy_lure.bind(String(lure.id)))
	_heading("CabinHeading", "For the cabin")
	for item: Dictionary in HarbourTrades.get_decor():
		_row("decor_%s" % item.id, Loc.t(String(item.name)), Loc.t(String(item.text)), _buy_decor.bind(String(item.id)))
	refresh()


func refresh() -> void:
	super.refresh()
	if _rows.is_empty():
		return
	var open := GameSession.has_facility(HarbourFacilities.CHANDLERY)
	var funds := GameSession.get_funds()
	for id: String in HarbourTrades.get_chandlery_upgrades():
		var button := _rows[id] as Button
		if GameSession.has_upgrade(id):
			button.text = "Fitted"
			button.disabled = true
		else:
			var price := GameSession.upgrade_price(id)
			button.text = Loc.t("Fit it (%s)") % GameSession.format_money(price)
			button.disabled = not open or price > funds or GameSession.upgrade_refusal(id) != ""
	var magic := _rows["magic_anchor"] as Button
	var magic_price := HarbourTrades.get_magic_anchor_price()
	magic.text = "Aboard" if GameSession.has_magic_anchor() else Loc.t("Buy (%s)") % GameSession.format_money(magic_price)
	magic.disabled = GameSession.has_magic_anchor() or not open or magic_price > funds
	for lure: Dictionary in FishingCatalog.get_default().lures:
		var button := _rows["lure_%s" % lure.id] as Button
		button.text = Loc.t("Buy (%s)  ·  %d aboard") % [GameSession.format_money(int(lure.price)),
			GameSession.get_fishing().get_lure_count(String(lure.id))]
		button.disabled = not open or int(lure.price) > funds
	for item: Dictionary in HarbourTrades.get_decor():
		var button := _rows["decor_%s" % item.id] as Button
		if GameSession.get_home().owns_decor(String(item.id)):
			button.text = "Yours"
			button.disabled = true
		else:
			button.text = Loc.t("Buy (%s)") % GameSession.format_money(int(item.price))
			button.disabled = not open or int(item.price) > funds
	_refresh_electronics(open, funds)


func _fit(id: String) -> void:
	var result := GameSession.install_upgrade(id)
	if result.error != "":
		notify(result.error)
		return
	time_requested.emit(float(result.minutes))
	SessionLog.write("upgrade_fitted", {"upgrade": id, "cost": result.cost, "port": String(GameSession.get_location_id()), "shop": "chandlery"})
	notify(Loc.t("%s fitted for %s.") % [Loc.t(String(BoatCare.get_upgrade(id).name)), GameSession.format_money(int(result.cost))])
	refresh()


func _buy_magic() -> void:
	var error := GameSession.buy_magic_anchor()
	if error != "":
		notify(error)
		return
	SessionLog.write("upgrade_fitted", {"upgrade": "magic_anchor", "cost": HarbourTrades.get_magic_anchor_price(),
		"port": String(GameSession.get_location_id()), "shop": "chandlery"})
	notify("The Magic Anchor is aboard. Choose it at the windlass when the water is deep.")
	refresh()


func _buy_lure(id: String) -> void:
	var error := GameSession.buy_lure(id)
	notify(error if error != "" else Loc.t("Bought a %s. You have %d.") % [Loc.t(String(FishingCatalog.get_default().get_lure(id).name)).to_lower(),
		GameSession.get_fishing().get_lure_count(id)])
	refresh()


func _buy_decor(id: String) -> void:
	var error := GameSession.buy_decor(id)
	if error != "":
		notify(error)
		return
	SessionLog.write("decor_bought", {"item": id, "port": String(GameSession.get_location_id())})
	notify(Loc.t("%s is yours. Show it aboard with \"Make it home\" (Q, in the cabin).") % Loc.t(String(HarbourTrades.get_decor_item(id).name)))
	refresh()


# --- Electronics (I026 stage 03) ---------------------------------------------------------------

func _add_electronics() -> void:
	_heading("ElectronicsHeading", "Electronics")
	for package in InstrumentPackage.get_all():
		_row("instruments_%s" % package.id, package.get_display_name(), package.get_text(), _on_instruments.bind(package.id))
	if not GameSession.instruments_changed.is_connected(refresh):
		GameSession.instruments_changed.connect(refresh)


func _refresh_electronics(open: bool, funds: int) -> void:
	var fitted := GameSession.get_instrument_package().id
	for package in InstrumentPackage.get_all():
		var button := _rows.get("instruments_%s" % package.id) as Button
		if button == null:
			continue
		if package.id == fitted:
			button.text = "Fitted"
			button.disabled = true
		elif GameSession.owns_instrument_package(package.id):
			button.text = "Fit it (yours)"
			button.disabled = false
		else:
			button.text = Loc.t("Buy and fit (%s)") % GameSession.format_money(package.price)
			button.disabled = not open or package.price > funds


func _on_instruments(id: String) -> void:
	var package := InstrumentPackage.get_package(id)
	var owned := GameSession.owns_instrument_package(id)
	var error := GameSession.fit_instrument_package(id) if owned else GameSession.buy_instrument_package(id)
	if error != "":
		notify(error)
		return
	var boat := GameSession.get_vessel_definition().display_name
	if owned:
		notify(Loc.t("%s fitted to the %s.") % [package.get_display_name(), boat])
	else:
		SessionLog.write("upgrade_fitted", {"upgrade": "instruments_%s" % id, "cost": package.price, "port": String(GameSession.get_location_id()), "shop": "chandlery"})
		notify(Loc.t("%s fitted to the %s for %s. It is yours for any boat.") % [package.get_display_name(), boat, GameSession.format_money(package.price)])
	refresh()
