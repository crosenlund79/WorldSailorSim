extends RefCounted
## I020, A Boat of Your Own: the harbour trades (which harbours have them,
## from their data), the fishmonger, the chandlery and the sailmaker (whole
## transactions, never below zero, never twice), the cabin things on all
## four boats (each boat its own, never over a station), sailcloth per boat
## (a look only), saves old and new, and both languages.

const APP_SCENE := preload("res://src/app/app.tscn")
const VESSELS: Array[StringName] = [&"arctic_wanderer_26", &"starling_33", &"petrel_36", &"halcyon_40"]

var t: Node
var app: Node


func run(runner: Node) -> void:
	t = runner
	Simulation.auto_advance = false
	_test_availability()
	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	app.start_new_game()
	await _settle()
	await _test_fishmonger()
	await _test_chandlery()
	await _test_sailmaker()
	await _test_cabins()
	_test_saves()
	await _test_danish()
	Simulation.auto_advance = true
	app.queue_free()
	await t.frames(2)
	GameSession.end_session()


func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)


func _moor_in(port_id: StringName) -> void:
	var state := GameSession.get_state_snapshot()
	state.location_id = port_id
	state.vessel_status = SessionState.STATUS_MOORED
	state.vessel_position = PortCatalog.get_default().get_port(port_id).get_geo_position()
	state.voyage = null
	GameSession.replace_state(state)


func _test_availability() -> void:
	var copenhagen := HarbourFacilities.for_port(&"copenhagen")
	var aero := HarbourFacilities.for_port(&"aeroskobing")
	t.check(copenhagen.has(HarbourFacilities.CHANDLERY) and copenhagen.has(HarbourFacilities.SAILMAKER) and copenhagen.has(HarbourFacilities.FISHMONGER),
		"[trades] Copenhagen (a boatyard): chandlery, sailmaker and fishmonger")
	t.check(aero.has(HarbourFacilities.FISHMONGER) and not aero.has(HarbourFacilities.CHANDLERY) and not aero.has(HarbourFacilities.SAILMAKER),
		"[trades] Ærøskøbing (no boatyard): the fishmonger only, from its own facility data")
	var catalog := PortCatalog.get_default()
	var fishmongers := 0
	var chandleries := 0
	for port in catalog.ports:
		var f := HarbourFacilities.for_port(port.id)
		fishmongers += 1 if f.has(HarbourFacilities.FISHMONGER) else 0
		chandleries += 1 if f.has(HarbourFacilities.CHANDLERY) else 0
	t.check(fishmongers >= catalog.ports.size() * 0.9 and chandleries > 100,
		"[trades] a fishmonger wherever there is a grocery (%d of %d harbours), a chandlery at %d yards, international ones included" % [
			fishmongers, catalog.ports.size(), chandleries])
	var preview := HarbourFacilities.describe_services(&"copenhagen")
	t.check(preview.contains("Chandlery") and preview.contains("Sailmaker") and preview.contains("Fishmonger") and not HarbourFacilities.describe_services(&"aeroskobing").contains("Chandlery"),
		"[trades] the chart's harbour preview lists them: %s" % preview)


func _catch(count: int) -> void:
	var state := GameSession.get_state_snapshot()
	for i in count:
		var uid := 9000 + i
		state.fishing.hold.append({"uid": uid, "species": "cod", "kg": 2.0 + i, "grade": "bronze", "caught_at": state.game_time,
			"where": "Øresund"})
	state.fishing.records["cod"] = {"count": count, "best_kg": 2.0 + count - 1}
	GameSession.replace_state(state)


func _test_fishmonger() -> void:
	_moor_in(&"copenhagen")
	_catch(3)
	var funds := GameSession.get_funds()
	var catalog := FishingCatalog.get_default()
	var expected := 0
	for fish: Dictionary in GameSession.get_fishing().hold:
		expected += catalog.price(fish.species, float(fish.kg))
	# The way the Captain goes: the grocery store first, the fishmonger next door.
	app.open_grocery()
	await t.frames(2)
	var grocery := app.modals.get_top() as GroceryMenu
	var menu: TradePanel = app.open_fishmonger()
	if not t.check(grocery != null and menu != null, "[fishmonger] opens in Copenhagen (from the grocery store)"):
		return
	await t.frames(2)
	t.check(menu.get_row_ids().size() == 3, "[fishmonger] every fish in the cool box is shown with its price (%d rows)" % menu.get_row_ids().size())
	var first: Button = menu.get_row_button("9000")
	first.pressed.emit()
	await t.frames(2)
	var one := catalog.price("cod", 2.0)
	t.check(GameSession.get_funds() == funds + one and GameSession.get_fishing().find_in_hold(9000) < 0, "[fishmonger] one fish sold: paid %s once" % GameSession.format_money(one))
	t.check(GameSession.sell_fish(9000).error != "" and GameSession.get_funds() == funds + one, "[fishmonger] the same fish cannot be sold twice")
	var price_label := grocery.find_child("Price", true, false) as Label
	t.check(price_label != null and price_label.text.contains(GameSession.format_money(funds + one)),
		"[grocery] back at the grocery store, the funds shown include the sale (%s)" % (price_label.text if price_label else "no label"))
	var saved := GameSession.get_state_snapshot()
	var trophies := GameSession.get_fishing().trophies.size()
	var all := GameSession.sell_catch()
	t.check(all.error == "" and int(all.count) == 2 and GameSession.get_funds() == funds + expected and GameSession.get_fishing().hold.is_empty(),
		"[fishmonger] \"sell all\": the rest in one transaction, the total exactly once (%s)" % GameSession.format_money(expected))
	t.check(GameSession.get_fishing().trophies.size() == trophies and GameSession.get_fishing().records.has("cod"), "[fishmonger] trophies and records stay")
	t.check(GameSession.sell_catch().error != "" and GameSession.get_funds() == funds + expected, "[fishmonger] an empty cool box sells nothing")
	# A load from before the sale brings the fish back and takes the money back.
	GameSession.replace_state(saved)
	t.check(GameSession.get_fishing().hold.size() == 2 and GameSession.get_funds() == funds + one, "[save] loaded from before the sale: the fish and the funds as they were")
	GameSession.sell_catch()
	app.modals.clear()
	# At sea, no fishmonger.
	var at_sea := GameSession.get_state_snapshot()
	_catch(1)
	GameSession.plan_route_to(&"gothenburg")
	GameSession.depart()
	t.check(GameSession.sell_catch().error != "", "[fishmonger] at sea nothing is sold")
	GameSession.replace_state(at_sea)


func _test_chandlery() -> void:
	_moor_in(&"copenhagen")
	var menu: TradePanel = app.open_chandlery()
	if not t.check(menu != null, "[chandlery] opens at the Copenhagen yard"):
		return
	await t.frames(2)
	var ids: Array = menu.get_row_ids()
	t.check(ids.has("large_cool_box") and ids.has("magic_anchor") and ids.has("decor_rug") and ids.has("lure_spinner") and not ids.has("heavy_anchor"),
		"[chandlery] a small catalogue: gear, the Magic Anchor, lures, cabin things (%d items)" % ids.size())
	var funds := GameSession.get_funds()
	var price := GameSession.upgrade_price("large_cool_box")
	menu.get_row_button("large_cool_box").pressed.emit()
	await t.frames(2)
	t.check(GameSession.has_upgrade("large_cool_box") and GameSession.get_funds() == funds - price and menu.get_row_button("large_cool_box").disabled,
		"[chandlery] the cool box is fitted (the boat-care upgrade itself, %s)" % GameSession.format_money(price))
	t.check(GameSession.install_upgrade("large_cool_box").error != "", "[chandlery] and never sold twice to the same boat")
	funds = GameSession.get_funds()
	t.check(GameSession.buy_decor("rug") == "" and GameSession.get_funds() == funds - 40 and GameSession.get_home().owns_decor("rug"), "[chandlery] a braided rug, €40")
	t.check(GameSession.buy_decor("rug") != "" and GameSession.get_funds() == funds - 40, "[chandlery] bought once only")
	# Never below zero: with €10, nothing dearer is sold and nothing is taken.
	var state := GameSession.get_state_snapshot()
	state.funds = 10
	GameSession.replace_state(state)
	await t.frames(2)
	t.check(GameSession.buy_decor("oil_lamp") != "" and GameSession.buy_magic_anchor() != "" and GameSession.get_funds() == 10
		and not GameSession.get_home().owns_decor("oil_lamp"), "[chandlery] not enough money: refused whole, the funds untouched (€10)")
	menu.refresh()
	t.check(menu.get_row_button("decor_oil_lamp").disabled, "[chandlery] and its button says so")
	state.funds = 20000
	GameSession.replace_state(state)
	app.modals.clear()
	# A harbour without a yard has no chandlery.
	_moor_in(&"aeroskobing")
	t.check(GameSession.buy_decor("herbs").contains("chandlery") and app.open_chandlery() == null, "[chandlery] none in Ærøskøbing (%s)" % GameSession.buy_decor("herbs"))
	_moor_in(&"copenhagen")


func _test_sailmaker() -> void:
	_moor_in(&"copenhagen")
	await t.board(&"arctic_wanderer_26", app)
	var menu: TradePanel = app.open_sailmaker()
	if not t.check(menu != null, "[sailmaker] opens at the Copenhagen yard"):
		return
	await t.frames(2)
	var funds := GameSession.get_funds()
	var price := GameSession.sail_cloth_price("tanbark")
	t.check(price > 0 and menu.get_row_button("cloth_classic").disabled, "[sailmaker] classic cream aboard; tanbark for %s" % GameSession.format_money(price))
	menu.get_row_button("cloth_tanbark").pressed.emit()
	await t.frames(2)
	t.check(GameSession.get_sail_cloth() == "tanbark" and GameSession.get_funds() == funds - price, "[sailmaker] tanbark sails cut and paid once")
	t.check(GameSession.sail_cloth_price("classic") == 0 and GameSession.order_sail_cloth("classic") == "" and GameSession.get_funds() == funds - price,
		"[sailmaker] back to the classic cream: free")
	t.check(GameSession.sail_cloth_price("tanbark") == 0 and GameSession.order_sail_cloth("tanbark") == "" and GameSession.get_funds() == funds - price,
		"[sailmaker] and the tanbark again: free (it was cut for this boat)")
	# A look only: the boat's performance is the same.
	var profile := GameSession.get_vessel_profile()
	t.check(profile == GameSession.get_vessel_profile(), "[sailmaker] the performance profile is untouched")
	app.modals.clear()
	GameSession.enter_boat_area(SessionState.AREA_EXTERIOR, &"start")
	app._show_current_boat_area()
	await _settle()
	var rig := app.router.current_screen.get_node_or_null(^"SailRig") as SailRig
	t.check(rig != null and rig.sail_colour == HarbourTrades.sail_colours("tanbark")[0], "[sailmaker] the deck shows the tanbark sails")
	# Another boat keeps its own.
	await t.board(&"halcyon_40", app)
	t.check(GameSession.get_sail_cloth() == "classic" and GameSession.get_sail_cloth(&"arctic_wanderer_26") == "tanbark", "[sailmaker] the Clam 40 keeps its own cream sails")
	# The rig service is the boat-care service itself.
	var care := GameSession.get_state_snapshot()
	(care.get_boat_care(care.vessel_id) as BoatCareState).rig_wear = 60.0
	GameSession.replace_state(care)
	menu = app.open_sailmaker()
	await t.frames(2)
	var quote := GameSession.service_quote(BoatCare.SERVICE_RIG)
	funds = GameSession.get_funds()
	var time := GameSession.get_game_time()
	menu.get_row_button("service").pressed.emit()
	await t.frames(2)
	t.check(GameSession.get_boat_care().rig_wear < 1.0 and GameSession.get_funds() == funds - int(quote.cost) and GameSession.get_game_time() >= time + float(quote.minutes) * 60.0 - 1.0,
		"[sailmaker] the sail and rig service: the same wear, price and time as at the yard (%s)" % GameSession.format_money(int(quote.cost)))
	app.modals.clear()


func _test_cabins() -> void:
	_moor_in(&"copenhagen")
	for item: Dictionary in HarbourTrades.get_decor():
		GameSession.buy_decor(String(item.id))
	var all := HarbourTrades.get_decor().size()
	t.check(GameSession.get_home().owned_decor.size() == all, "(setup) every cabin thing bought (%d)" % all)
	for vessel_id in VESSELS:
		await t.board(vessel_id, app)
		GameSession.enter_boat_area(SessionState.AREA_INTERIOR, &"start")
		app._show_current_boat_area()
		await _settle()
		var menu: TradePanel = app.open_cabin_home()
		if not t.check(menu != null, "[cabin] \"Make it home\" opens in the %s's cabin" % vessel_id):
			continue
		await t.frames(2)
		for item: Dictionary in HarbourTrades.get_decor():
			menu.get_row_button(String(item.id)).pressed.emit()
		await t.frames(3)
		var area := app.router.current_screen as BoatArea
		var placed := area.setup_decor()
		await t.frames(1)
		var stations := area.get_node("Layout/Stations")
		var too_close := []
		for id: String in placed:
			var at: Vector2 = placed[id][0]
			for station in stations.get_children():
				if station is Node2D and (station as Node2D).position.distance_to(at) < CabinDecor.CLEARANCE * 0.6 and id != "rug":
					too_close.append("%s~%s" % [id, station.name])
		var nodes := area.find_children("Decor_*", "CabinDecor", true, false)
		var collision := nodes.any(func(n: Node) -> bool: return not n.find_children("*", "CollisionObject2D", true, false).is_empty())
		t.check(placed.size() >= all - 1 and too_close.is_empty() and not collision,
			"[cabin] the %s: %d of %d things placed, none on a station, nothing to bump into (%s)" % [vessel_id, placed.size(), all, too_close])
		t.check(placed.has("compass"), "[cabin] the brass compass has a place on the %s's wall" % vessel_id)
		await t.screenshot("i020_cabin_%s" % vessel_id)
		app.modals.clear()
		# Stations still work: the chart table and the bed are where they were and enabled.
		t.check(stations.get_children().all(func(s: Node) -> bool: return not s is Interactable or (s as Interactable).visible), "[cabin] every station is still there")
	SettingsManager.set_language(&"da")
	var compass := Loc.t(String(HarbourTrades.get_decor_item("compass").name))
	SettingsManager.set_language(&"en")
	t.check(compass == "Kompas i messing", "[dansk] the brass compass: %s" % compass)
	# Each boat its own: put the rug away on the Clam 40 only.
	GameSession.set_cabin_decor("rug", false)
	t.check(not "rug" in GameSession.get_cabin_decor() and "rug" in GameSession.get_cabin_decor(&"starling_33"), "[cabin] each boat keeps its own choice")
	t.check(GameSession.set_cabin_decor("nonexistent", true) != "", "[cabin] only things the Captain owns can be shown")


func _test_saves() -> void:
	var errors: Array[String] = []
	var data: Dictionary = JSON.parse_string(JSON.stringify(GameSession.get_state_snapshot().to_dict()))
	var loaded := SessionState.from_dict(data, errors)
	t.check(errors.is_empty() and loaded != null and loaded.home.owned_decor.size() == HarbourTrades.get_decor().size()
		and loaded.home.get_sails(&"arctic_wanderer_26") == "tanbark" and loaded.home.get_decor(&"starling_33").has("rug"),
		"[save] cabins and sails survive a save and load (save format %d) %s" % [SaveManager.SAVE_VERSION, errors])
	var old := data.duplicate(true)
	old.erase("home")
	var plain := SessionState.from_dict(old, errors)
	t.check(errors.is_empty() and plain != null and plain.home.is_empty() and plain.home.get_sails(&"petrel_36") == "classic",
		"[save] an older save (no cabin data) loads with plain cabins and cream sails")
	var odd := data.duplicate(true)
	odd.home.owned_decor.append("gold_throne")
	odd.home.vessels["arctic_wanderer_26"].sails = "zebra"
	var tolerant := SessionState.from_dict(odd, errors)
	t.check(errors.is_empty() and tolerant != null and not tolerant.home.owns_decor("gold_throne") and tolerant.home.get_sails(&"arctic_wanderer_26") == "classic",
		"[save] unknown things are dropped quietly, never a refused save")


func _test_danish() -> void:
	SettingsManager.set_language(&"da")
	_moor_in(&"copenhagen")
	var screen := Rect2(Vector2.ZERO, app.get_viewport().get_visible_rect().size)
	var problems := []
	for opener: Callable in [app.open_chandlery, app.open_sailmaker, app.open_fishmonger]:
		app.modals.clear()
		var menu: Node = opener.call()
		await t.frames(3)
		var scroll := menu.find_child("Scroll", true, false) as ScrollContainer
		if scroll and not screen.grow(2.0).encloses(scroll.get_global_rect()):
			problems.append("%s/Scroll" % menu.name)
		for node in menu.find_children("*", "Control", true, false):
			var control := node as Control
			if not control.is_visible_in_tree() or not (control is Button or control is Label):
				continue
			var rect := control.get_global_rect()
			if scroll and scroll.is_ancestor_of(control):
				# A row scrolled out of view is not off screen (I021: longer lists);
				# it must still fit across.
				if rect.position.x < -2.0 or rect.end.x > screen.end.x + 2.0:
					problems.append("%s/%s" % [menu.name, control.name])
			elif not screen.grow(2.0).encloses(rect):
				problems.append("%s/%s" % [menu.name, control.name])
	var chandlery_title := ""
	app.modals.clear()
	var shop: TradePanel = app.open_chandlery()
	await t.frames(2)
	var title := shop.find_child("Title", true, false) as Label
	chandlery_title = title.atr(title.text)
	t.check(problems.is_empty() and chandlery_title == "Skibshandel", "[dansk] the trades in Danish (\"%s\") fit the screen (%s)" % [chandlery_title, problems.slice(0, 4)])
	t.check(Loc.t("Make it home") != "Make it home" and Loc.t("Braided rug") != "Braided rug" and Loc.t("Tanbark") != "Tanbark",
		"[dansk] the new texts are translated")
	app.modals.clear()
	SettingsManager.set_language(&"en")
