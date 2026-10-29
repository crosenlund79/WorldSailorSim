extends RefCounted
## I027 Tier 3, yacht accommodation: every boat's people data (Accommodation,
## data/vessels/accommodation.json) agrees with its drawn cabin - each
## sleeping place, cabin, heads and amenity names a node the cabin draws, and
## a boat that draws no cabin door claims no private cabin; the booking
## queries for I028 (safe and overnight guests, private cabins, the skipper's
## privacy, comfort, passage suitability); the size classes follow length,
## price and running costs, and the dearest boat is not best at everything;
## the boatyard shows life aboard in English and Danish; the passage
## readiness for the Pacific's longest leg (Galápagos to the Marquesas) per
## boat, and its fuel note.

const APP_SCENE := preload("res://src/app/app.tscn")
const STEADY := preload("res://tests/suites/test_steady_hands.gd")
const BOATS: Array[StringName] = [&"arctic_wanderer_26", &"starling_33", &"petrel_36", &"halcyon_40"]
## Amenity -> the nodes that may draw it (any one).
const AMENITY_NODES := {"galley": ["Galley", "GalleyAft", "GalleySide"], "chart_table": ["NavTable", "NavDesk"], "saloon_table": ["SaloonTable", "Table"],
	"lockers": ["StoragePort", "StorageStarboard", "Locker", "GuestLocker"], "fridge": ["Fridge"], "wardrobe": ["Wardrobe"], "desk": ["Desk"]}

var t: Node
var app: Node


func run(runner: Node) -> void:
	t = runner
	_test_data()
	_test_matches_the_art()
	_test_queries()
	_test_classes()
	_test_pacific()
	await _test_boatyard()


func _test_data() -> void:
	var missing: Array[String] = []
	var bad: Array[String] = []
	for id in VesselCatalog.get_default().get_ids():
		if not Accommodation.has_data(id):
			missing.append(String(id))
			continue
		var data := Accommodation.of(id)
		if not (StringName(data.comfort) in Accommodation.COMFORT_ORDER and StringName(data.passage) in Accommodation.PASSAGE_ORDER
				and StringName(data.size_class) in [Accommodation.SIZE_SMALL, Accommodation.SIZE_MEDIUM, Accommodation.SIZE_LARGE]):
			bad.append("%s: class, comfort or passage" % id)
		var skipper := 0
		for place: Dictionary in data.sleeping:
			skipper += 1 if String(place.get("for", "")) == Accommodation.FOR_SKIPPER else 0
			if not StringName(place.quality) in [Accommodation.QUALITY_BASIC, Accommodation.QUALITY_GOOD, Accommodation.QUALITY_FINE]:
				bad.append("%s: %s quality" % [id, place.id])
			if String(place.space) != Accommodation.SPACE_SHARED and Accommodation._cabin(id, String(place.space)).is_empty():
				bad.append("%s: %s in an unknown cabin" % [id, place.id])
		if skipper != 1:
			bad.append("%s: %d skipper's berths" % [id, skipper])
		if Accommodation.overnight_guest_count(id) + 1 > Accommodation.safe_persons(id):
			bad.append("%s: more sleep aboard than it safely carries" % id)
	t.check(missing.is_empty(), "[data] every boat in the catalogue has accommodation data %s" % [missing])
	t.check(bad.is_empty(), "[data] valid: classes, one skipper's berth, cabins known, never more aboard overnight than safe %s" % [bad])
	t.check(Accommodation.safe_persons(&"no_such_boat") == 1 and Accommodation.overnight_guest_count(&"no_such_boat") == 0,
		"[data] an unknown boat carries the skipper alone (no guests offered)")


## Every place in the data is drawn in the boat's cabin, and nothing is claimed
## that is not.
func _test_matches_the_art() -> void:
	for id in BOATS:
		var vessel := VesselCatalog.get_default().get_vessel(id)
		var cabin := (vessel.cabin_scene.instantiate() as Node)
		var visual := cabin.find_child("Visual", true, false)
		var furniture := cabin.find_child("FurnitureVisual", true, false)
		var labels := cabin.find_child("Labels", true, false)
		var problems: Array[String] = []
		if furniture == null:
			problems.append("no FurnitureVisual")
		else:
			var data := Accommodation.of(id)
			for place: Dictionary in data.sleeping:
				if furniture.get_node_or_null(NodePath(String(place.node))) == null:
					problems.append("berth %s (%s) not drawn" % [place.id, place.node])
			for head: Dictionary in data.heads:
				if furniture.get_node_or_null(NodePath(String(head.node))) == null:
					problems.append("heads %s not drawn" % head.node)
			for cabin_data: Dictionary in data.cabins:
				if labels == null or labels.get_node_or_null(NodePath(String(cabin_data.label_node))) == null:
					problems.append("cabin %s not drawn" % cabin_data.id)
			for amenity: String in data.amenities:
				if not (AMENITY_NODES.get(amenity, []) as Array).any(func(n: String) -> bool: return furniture.find_child(n, true, false) != null):
					problems.append("amenity %s not drawn" % amenity)
			# The other way round: what the cabin draws is in the data.
			var drawn_showers := furniture.find_children("*Shower*", "", true, false).size()
			if drawn_showers != int(data.showers):
				problems.append("%d showers drawn, %d in the data" % [drawn_showers, int(data.showers)])
			var drawn_cabins := labels.find_children("*Cabin", "", false, false).size() if labels else 0
			if drawn_cabins != (data.cabins as Array).size():
				problems.append("%d cabins drawn, %d in the data" % [drawn_cabins, (data.cabins as Array).size()])
			var drawn_heads := furniture.find_children("Heads", "", false, false).size() + furniture.find_children("Ensuite", "", false, false).size()
			if drawn_heads != Accommodation.heads_count(id):
				problems.append("%d heads drawn, %d in the data" % [drawn_heads, Accommodation.heads_count(id)])
		t.check(visual != null and problems.is_empty(), "[art] %s: every berth, cabin, heads and amenity in the data is drawn, and the drawn cabins, heads and showers are all in it %s" % [
			vessel.display_name, problems])
		cabin.free()


func _test_queries() -> void:
	var expected := {
		&"arctic_wanderer_26": [4, 3, 2, 0, false, &"simple", &"offshore"],
		&"starling_33": [6, 5, 2, 0, false, &"comfortable", &"ocean"],
		&"petrel_36": [5, 4, 2, 0, false, &"simple", &"offshore"],
		&"halcyon_40": [8, 7, 4, 1, true, &"spacious", &"ocean"],
	}
	for id: StringName in expected:
		var e: Array = expected[id]
		var got := [Accommodation.safe_persons(id), Accommodation.safe_guest_count(id), Accommodation.overnight_guest_count(id),
			Accommodation.private_guest_cabins(id), Accommodation.skipper_has_privacy(id), Accommodation.comfort_tier(id),
			Accommodation.passage_suitability(id)]
		t.check(got == e, "[queries] %s: safe %d (guests %d), overnight %d, private guest cabins %d, skipper's own cabin %s, %s, %s" % [
			id, got[0], got[1], got[2], got[3], got[4], got[5], got[6]])
	t.check(Accommodation.sleeping_places(&"arctic_wanderer_26") == 4 and Accommodation.safe_persons(&"halcyon_40") < Accommodation.sleeping_places(&"halcyon_40") + 3,
		"[queries] berths are not capacity: the 26 ft sleeps 4 but takes 2 guests overnight (the V-berth is the skipper's)")
	t.check(Accommodation.suits_passage(&"starling_33", Accommodation.PASSAGE_OCEAN) and not Accommodation.suits_passage(&"arctic_wanderer_26", Accommodation.PASSAGE_OCEAN)
		and Accommodation.suits_passage(&"arctic_wanderer_26", Accommodation.PASSAGE_COASTAL), "[queries] passage suitability: the Wing 33 is fitted for oceans, the 26 ft for offshore")
	t.check(Accommodation.heads_count(&"arctic_wanderer_26") == 0 and Accommodation.heads_count(&"halcyon_40") == 2,
		"[queries] heads as drawn: none in the 26 ft, two in the Clam 40")


## Small, medium, large: by length and price; the running costs follow; the
## dearest boat is not the best at everything.
func _test_classes() -> void:
	var order := {Accommodation.SIZE_SMALL: 0, Accommodation.SIZE_MEDIUM: 1, Accommodation.SIZE_LARGE: 2}
	var problems: Array[String] = []
	for a in BOATS:
		for b in BOATS:
			var va := VesselCatalog.get_default().get_vessel(a)
			var vb := VesselCatalog.get_default().get_vessel(b)
			if int(order[Accommodation.size_class(a)]) < int(order[Accommodation.size_class(b)]):
				if not (va.performance.length_ft < vb.performance.length_ft and va.price < vb.price):
					problems.append("%s below %s but not shorter and cheaper" % [a, b])
				if not (Economy.dues_per_night(&"copenhagen", va.performance.length_ft) < Economy.dues_per_night(&"copenhagen", vb.performance.length_ft)
						and Economy.burn_lph(a) <= Economy.burn_lph(b)):
					problems.append("%s below %s but not cheaper to run" % [a, b])
	t.check(problems.is_empty(), "[classes] small < medium < large by length, price, dues and fuel %s" % [problems])
	var clam := VesselCatalog.get_default().get_vessel(&"halcyon_40").performance
	var wing := VesselCatalog.get_default().get_vessel(&"starling_33").performance
	var frog := VesselCatalog.get_default().get_vessel(&"petrel_36").performance
	t.check(Accommodation.comfort_tier(&"halcyon_40") == Accommodation.COMFORT_SPACIOUS and clam.sail_speed_kn(14.0, 50.0) < wing.sail_speed_kn(14.0, 50.0)
		and frog.sail_speed_kn(14.0, 50.0) > clam.sail_speed_kn(14.0, 50.0),
		"[classes] the dearest boat is the roomiest, not the best: the Clam 40 points worst (%.1f kn at 50° in 14 kn; Wing %.1f, Frogleap %.1f)" % [
			clam.sail_speed_kn(14.0, 50.0), wing.sail_speed_kn(14.0, 50.0), frog.sail_speed_kn(14.0, 50.0)])


## The Pacific's longest leg per boat, on the world voyage's weather: which
## boats stow enough for it, and what the readiness says on the 26 ft.
func _test_pacific() -> void:
	WindField.get_default().test_override = Callable()  # the real wind and weather
	WeatherModel.get_default().clear_cache()
	Simulation.invalidate_estimates()
	var lines: Array[String] = []
	var spare_boats := 0
	for id in BOATS:
		_moor(&"puerto_ayora", id, 1.0)
		GameSession.plan_route_to(&"taiohae")
		var days := Simulation.estimate_route_seconds(GameSession.get_planned_route().path) / 86400.0
		var stores := GameSession.get_passage_store_days()
		spare_boats += 1 if stores - days >= 2.0 else 0
		lines.append("%s %.1f d (stows %d)" % [id, days, roundi(stores)])
	t.check(spare_boats >= 1, "[pacific] Galápagos -> Marquesas: a boat in the fleet crosses with days to spare (%s)" % ", ".join(lines))
	_moor(&"puerto_ayora", &"arctic_wanderer_26", 0.2)
	GameSession.buy_provisions(GameSession.get_passage_store_days())
	GameSession.plan_route_to(&"taiohae")
	var low := PassageReadiness.assess(GameSession.get_planned_route().path)
	var fuel_note := (low.items as Array).any(func(i: Dictionary) -> bool: return String(i.topic) == "fuel")
	_moor(&"puerto_ayora", &"arctic_wanderer_26", 1.0)
	GameSession.buy_provisions(GameSession.get_passage_store_days())
	GameSession.plan_route_to(&"taiohae")
	var full := PassageReadiness.assess(GameSession.get_planned_route().path)
	t.check(fuel_note and not (full.items as Array).any(func(i: Dictionary) -> bool: return String(i.topic) == "fuel")
		and float(full.hours) < float(low.hours),
		"[pacific] the 26 ft on a fifth of a tank: the readiness suggests filling up (%.1f d against %.1f d on a full tank)" % [
			float(low.hours) / 24.0, float(full.hours) / 24.0])
	var stores := (full.items as Array).filter(func(i: Dictionary) -> bool: return String(i.topic) == "stores")
	t.check(stores.size() == 1 and String(stores[0].text).contains("d"),
		"[pacific] the 26 ft's readiness speaks plainly about the stores (%s)" % (String(stores[0].text) if stores.size() == 1 else "-"))
	t.use_calm_wind()
	GameSession.end_session()


func _moor(port: StringName, vessel_id: StringName, fuel_share: float) -> void:
	GameSession.start_new_session()
	var state := GameSession.get_state_snapshot()
	state.vessel_id = vessel_id
	state.wind_seed = 16
	state.location_id = port
	state.vessel_position = PortCatalog.get_default().get_port(port).get_geo_position()
	state.fuel[vessel_id] = fuel_share * Economy.tank_l(vessel_id)
	GameSession.replace_state(state)
	Simulation.invalidate_estimates()


func _test_boatyard() -> void:
	app = APP_SCENE.instantiate()
	t.add_child(app)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.frames(4)
	app.start_new_game()
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.frames(4)
	for language: StringName in [&"en", &"da"]:
		SettingsManager.set_language(language)
		app.modals.clear()
		await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
		app.open_boatyard()
		await t.frames(3)
		var yard := app.modals.get_top() as BoatyardMenu
		if not t.check(yard != null, "[boatyard %s] the boatyard opens in Copenhagen" % language):
			break
		var problems: Array[String] = []
		for id in BOATS:
			yard.select(id)
			await t.frames(2)
			var specs := yard.find_child("Specs", true, false) as GridContainer
			var texts := PackedStringArray()
			for child in specs.get_children():
				texts.append((child as Label).text)
			for row: Array in Accommodation.describe_rows(id):
				if not texts.has(String(row[0])) or not texts.has(String(row[1])):
					problems.append("%s: %s" % [id, row[0]])
			if language == &"da":
				for text in texts:
					var phrase := STEADY.english_phrase(text)
					if not phrase.is_empty():
						problems.append("%s shows English %s" % [id, phrase])
			var panel := specs.get_parent() as Control
			if not app.get_viewport().get_visible_rect().encloses(panel.get_global_rect()):
				problems.append("%s: the details leave the screen" % id)
		t.check(problems.is_empty(), "[boatyard %s] every boat shows its berths, guests, life aboard and passages, inside the screen %s" % [language, problems])
		yard.select(&"halcyon_40")
		await t.frames(2)
		await t.screenshot("i027_boatyard_accommodation_%s" % language)
	SettingsManager.set_language(&"en")
	app.modals.clear()
	app.queue_free()
	await t.frames(2)
	GameSession.end_session()
