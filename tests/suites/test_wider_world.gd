extends RefCounted
## I021, A Wider, Warmer World: the new harbours (real places with a way to
## open water, facilities, both languages), what every harbour looks like
## beyond the pontoon (chosen per harbour, never by continent; missing art
## falls back to the plain quay), the special harbours and their chart mark,
## the arrival card, the new fish (where they live, their art, prices, names,
## saves) and the new cabin things, with old saves still loading.

const APP_SCENE := preload("res://src/app/app.tscn")
const NEW_HARBOURS: Array[StringName] = [&"dingle", &"stornoway", &"isafjordur", &"lunenburg", &"st_johns", &"valletta",
	&"symi", &"essaouira", &"dakar", &"st_helena", &"cape_town", &"zanzibar", &"port_louis", &"galle", &"langkawi", &"hobart"]
const NEW_FISH: Array[String] = ["pollack", "halibut", "red_mullet", "dentex", "bluefish", "striped_bass", "giant_trevally",
	"wahoo", "spanish_mackerel", "grouper"]
const NEW_DECOR: Array[String] = ["model_ship", "sea_glass", "barometer"]

var t: Node
var app: Node
var looks: HarbourLooks


func run(runner: Node) -> void:
	t = runner
	looks = HarbourLooks.get_default()
	_test_new_harbours()
	_test_looks()
	_test_specials()
	_test_missing_art()
	_test_fish()
	_test_decor_data()
	_test_old_saves()
	Simulation.auto_advance = false
	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	app.start_new_game()
	await _settle()
	await _test_moored_views()
	await _test_arrival_card()
	_test_chart_details()
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


# --- Harbours ----------------------------------------------------------------------------------

func _test_new_harbours() -> void:
	var catalog := PortCatalog.get_default()
	var missing := NEW_HARBOURS.filter(func(id: StringName) -> bool: return catalog.get_port(id) == null)
	t.check(missing.is_empty() and catalog.ports.size() == 239, "[harbours] the 16 new harbours are in the catalogue (%d in all; missing %s)" % [catalog.ports.size(), missing])
	var problems := []
	for id in NEW_HARBOURS:
		var port := catalog.get_port(id)
		if port == null:
			continue
		if port.description.length() < 40 or not port.source.begins_with("GeoNames") or not HarbourFacilities.for_port(id).has(HarbourFacilities.GROCERY):
			problems.append(id)
	t.check(problems.is_empty(), "[harbours] each has a sentence about the place, its source and a grocery store (%s)" % [problems])
	# Real tiers, not everything everywhere: Cape Town hauls out, Symi has no boatyard.
	t.check(HarbourFacilities.for_port(&"cape_town").has(HarbourFacilities.HAUL_OUT) and not HarbourFacilities.for_port(&"symi").has(HarbourFacilities.BOATYARD),
		"[harbours] facilities follow the harbour's size (Cape Town hauls out; Symi has no boatyard)")
	SettingsManager.set_language(&"da")
	var da_name := catalog.get_display_name(&"cape_town")
	var da_text := catalog.get_port(&"valletta").get_description()
	SettingsManager.set_language(&"en")
	t.check(da_name == "Kapstaden" and da_text.begins_with("Valletta på Malta"), "[dansk] \"%s\" · \"%s\"" % [da_name, da_text.left(40)])


# --- Looks -------------------------------------------------------------------------------------

func _test_looks() -> void:
	var catalog := PortCatalog.get_default()
	var without := []
	for port in catalog.ports:
		if looks.look_of(port.id).is_empty() or not looks.looks.has(String(looks.look_of(port.id))):
			without.append(port.id)
	t.check(without.is_empty(), "[looks] every one of the %d harbours has a look from the table (%s)" % [catalog.ports.size(), without.slice(0, 5)])
	var no_image := []
	for look: String in looks.looks:
		if not ResourceLoader.exists(String(looks.looks[look].texture)):
			no_image.append(look)
	t.check(looks.looks.size() >= 6 and no_image.is_empty(), "[looks] %d looks, each with its finished illustration (%s)" % [looks.looks.size(), no_image])
	# Chosen by what the place looks like, not by its continent.
	t.check(looks.look_of(&"wellington") == looks.look_of(&"bergen") and looks.look_of(&"willemstad") == looks.look_of(&"copenhagen")
		and looks.look_of(&"hobart") == looks.look_of(&"aberdeen"),
		"[looks] New Zealand timber like Norway's, Willemstad's gables like Denmark's, Hobart's sandstone like Aberdeen's granite town")
	var europe := {}
	for id: StringName in [&"copenhagen", &"bergen", &"oban", &"naples", &"mykonos", &"horta"]:
		europe[looks.look_of(id)] = true
	t.check(europe.size() == 6 and looks.look_of(&"essaouira") == looks.look_of(&"zanzibar") and looks.look_of(&"dakar") != looks.look_of(&"essaouira"),
		"[looks] six European harbours, six different looks; Essaouira and Zanzibar share stone town; Dakar is not Morocco")
	# The look's art is built once and shared: repeated visits cost nothing new.
	var a := looks.art_for(&"dingle")
	var b := looks.art_for(&"stornoway")
	t.check(a != null and a == b and a.get_landmarks()[0].texture != null, "[looks] two harbours of one look share one illustration (built once)")
	SettingsManager.set_language(&"da")
	var title := looks.look_title(&"nordic_timber")
	SettingsManager.set_language(&"en")
	t.check(title == "Nordisk træhavn", "[dansk] the look's name: %s" % title)


# --- Special harbours ---------------------------------------------------------------------------

func _test_specials() -> void:
	var own := []
	for port in PortCatalog.get_default().ports:
		var art := HarbourArt.for_port(port.id)
		if art and not art.get_landmarks().is_empty():
			own.append(String(port.id))
	own.sort()
	var marked: Array = looks.special.keys()
	marked.sort()
	t.check(own == marked and own.size() == 6, "[special] the special harbours are exactly those with their own illustration (%s)" % [marked])
	t.check(not looks.is_special(&"kiel") and not looks.is_special(&"dingle") and looks.is_special(&"valletta"),
		"[special] ordinary harbours (Kiel, new Dingle) stay ordinary; Valletta is special")
	var english := looks.special_note(&"symi")
	SettingsManager.set_language(&"da")
	var dansk := looks.special_note(&"symi")
	var line := WorldMap._special_line(&"symi")
	SettingsManager.set_language(&"en")
	t.check(english.begins_with("an illustrated arrival") and dansk.begins_with("en illustreret ankomst") and line.contains("Særlig havn"),
		"[special] why, in both languages (\"%s\")" % dansk)
	t.check(WorldMap._special_line(&"kiel") == "", "[special] an ordinary harbour's details say nothing extra")
	for id: String in marked:  # their own art is drawn instead of the look's
		var art := looks.art_for(StringName(id))
		if not t.check(art != null and art.port_id == StringName(id), "[special] %s shows its own illustration" % id):
			return


func _test_missing_art() -> void:
	var broken := HarbourLooks.new()
	broken.looks = {"nowhere": {"title": "Nowhere", "texture": "res://assets/harbours/looks/no_such_picture.png"}}
	broken.harbours = {"kiel": "nowhere", "lohals": "not_a_look"}
	t.check(broken.art_for(&"kiel") == null and broken.art_for(&"lohals") == null and broken.picture_for(&"kiel") == null
		and broken.art_for(&"copenhagen") != null, "[looks] a missing picture or look: the plain quay, no crash (and a harbour's own art still shows)")


# --- Fish ---------------------------------------------------------------------------------------

func _test_fish() -> void:
	var catalog := FishingCatalog.get_default()
	var regions := {}
	for port in PortCatalog.get_default().ports:
		regions[port.region] = true
	var problems := []
	for id in NEW_FISH:
		var fish := catalog.get_species(id)
		if fish.is_empty() or not FishArt.has_art(id) or fish.regions.is_empty() \
				or not (fish.regions as Array).all(func(r: String) -> bool: return regions.has(r)) or float(fish.kg[0]) >= float(fish.kg[1]):
			problems.append(id)
	t.check(problems.is_empty(), "[fish] the 10 new fish: in the catalogue, with art, in real regions of the chart, sensible sizes (%s)" % [problems])
	# Each new region has fish, and the new fish are caught where they live.
	var where := {&"lunenburg": "striped_bass", &"zanzibar": "spanish_mackerel", &"langkawi": "giant_trevally", &"valletta": "dentex",
		&"isafjordur": "halibut", &"dakar": "bluefish", &"st_helena": "wahoo", &"stornoway": "pollack"}
	var not_here := []
	for port_id: StringName in where:
		var geo := PortCatalog.get_default().get_port(port_id).get_geo_position()
		var names := catalog.candidates(geo, FishingState.MODE_TROLLING, "spoon") + catalog.candidates(geo, FishingState.MODE_STATIONARY, "jig")
		if not names.any(func(c: Dictionary) -> bool: return c.species == where[port_id]):
			not_here.append("%s@%s" % [where[port_id], port_id])
	t.check(not_here.is_empty(), "[fish] caught where they live: striped bass off Lunenburg, Spanish mackerel off Zanzibar, GT at Langkawi … (%s)" % [not_here])
	var kiel := PortCatalog.get_default().get_port(&"kiel").get_geo_position()
	var baltic := catalog.candidates(kiel, FishingState.MODE_TROLLING, "spoon").map(func(c: Dictionary) -> String: return c.species)
	t.check(not NEW_FISH.any(func(id: String) -> bool: return id in baltic), "[fish] and not where they don't: none of them in the Baltic off Kiel")
	# Prices stay in the game's range: a new rare fish is worth about what an old rare one is.
	t.check(catalog.price("grouper", 5.0) <= catalog.price("yellowfin", 15.0) and catalog.price("red_mullet", 0.3) < catalog.price("cod", 4.0),
		"[fish] prices in line with the old catch (grouper %s, red mullet %s)" % [catalog.price("grouper", 5.0), catalog.price("red_mullet", 0.3)])
	SettingsManager.set_language(&"da")
	var da := [catalog.get_species_name("halibut"), catalog.get_species_name("pollack"), catalog.get_species_name("red_mullet")]
	SettingsManager.set_language(&"en")
	t.check(da == ["Helleflynder", "Lubbe", "Stribet mulle"], "[dansk] fish names: %s" % [da])
	# A record of a new fish survives a save.
	var fishing := FishingState.new()
	fishing.records["wahoo"] = {"count": 1, "best_kg": 21.5}
	var errors: Array[String] = []
	var copy := FishingState.from_dict(JSON.parse_string(JSON.stringify(fishing.to_dict())), errors)
	t.check(copy != null and errors.is_empty() and float(copy.records.wahoo.best_kg) == 21.5, "[save] a wahoo record is saved and loaded")


# --- Cabin things --------------------------------------------------------------------------------

func _test_decor_data() -> void:
	var ids := HarbourTrades.get_decor().map(func(d: Dictionary) -> String: return String(d.id))
	var missing := NEW_DECOR.filter(func(id: String) -> bool: return not id in ids)
	var prices := NEW_DECOR.map(func(id: String) -> int: return int(HarbourTrades.get_decor_item(id).price))
	t.check(missing.is_empty() and prices.all(func(p: int) -> bool: return p >= 15 and p <= 80), "[cabin] three new cabin things at modest prices %s" % [prices])
	SettingsManager.set_language(&"da")
	var name := Loc.t(String(HarbourTrades.get_decor_item("barometer").name))
	SettingsManager.set_language(&"en")
	t.check(name == "Barometer i messing", "[dansk] %s" % name)


func _test_old_saves() -> void:
	# A save from before I021 (no new harbour, fish or thing) loads as it was, and a
	# save made in one of the new harbours loads too.
	var errors: Array[String] = []
	var old := SessionState.create_new(&"copenhagen", SessionState.AREA_INTERIOR, &"start")
	var data: Dictionary = JSON.parse_string(JSON.stringify(old.to_dict()))
	var loaded := SessionState.from_dict(data, errors)
	t.check(loaded != null and errors.is_empty(), "[save] an old save loads unchanged (format %d)" % SaveManager.SAVE_VERSION)
	old.location_id = &"zanzibar"
	old.vessel_position = PortCatalog.get_default().get_port(&"zanzibar").get_geo_position()
	errors.clear()
	loaded = SessionState.from_dict(JSON.parse_string(JSON.stringify(old.to_dict())), errors)
	t.check(loaded != null and loaded.location_id == &"zanzibar", "[save] a save in Zanzibar loads in Zanzibar")


# --- In the game ---------------------------------------------------------------------------------

func _deck() -> BoatArea:
	app.modals.clear()
	GameSession.enter_boat_area(SessionState.AREA_EXTERIOR, &"start")
	app._show_current_boat_area()
	await _settle()
	return app.router.current_screen as BoatArea


func _test_moored_views() -> void:
	var counts := []
	var shown := {}
	for port_id: StringName in [&"valletta", &"dingle", &"zanzibar", &"copenhagen", &"suva", &"nukualofa", &"valletta", &"dingle"]:
		_moor_in(port_id)
		var deck := await _deck()
		var dressing := deck.find_child("HarbourDressing", true, false) as HarbourDressing
		if not t.check(dressing != null, "(setup) the harbour is dressed at %s" % port_id):
			return
		var landmarks := dressing.get_landmarks()
		shown[port_id] = landmarks[0].title if not landmarks.is_empty() else ""
		counts.append(deck.get_tree().get_node_count())
	t.check(shown[&"valletta"] == "Grand Harbour bastions" and shown[&"dingle"] == "Stone harbour of the Atlantic coast"
		and shown[&"zanzibar"] == "Stone town harbour" and shown[&"copenhagen"] == "Nyhavn",
		"[moored] each harbour shows its own view: %s" % [shown])
	t.check(shown[&"suva"] != "" and shown[&"nukualofa"] != "", "[moored] both sides of the date line (Suva, Nuku'alofa) show theirs")
	t.check(int(counts[-1]) <= int(counts[1]) + 5, "[moored] mooring again and again adds nothing (nodes %s)" % [counts])


func _test_arrival_card() -> void:
	_moor_in(&"symi")
	app.toasts.clear()
	app._on_arrived(&"symi")
	await t.frames(2)
	var card: Node = app.toasts.find_child("ArrivalCard", true, false)
	var text := "\n".join(app.toasts.get_messages())
	t.check(card != null and card.find_child("Picture", true, false) != null and text.contains("Arrived in Symi.") and text.contains("neoclassical"),
		"[arrival] a card with the harbour's picture, the arrival and a line about the place")
	t.check(card != null and (card as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE, "[arrival] it never blocks: clicks go through, it fades by itself")
	app.toasts.clear()
	SettingsManager.set_language(&"da")
	app._on_arrived(&"cape_town")
	await t.frames(2)
	text = "\n".join(app.toasts.get_messages())
	SettingsManager.set_language(&"en")
	t.check(text.contains("Kapstaden") and text.contains("Taffelbjerget"), "[dansk] the arrival card in Danish")
	app.toasts.clear()
	await _settle()


func _test_chart_details() -> void:
	var router := SeaRouter.get_default()
	var route := router.plan_route(&"suva", PortCatalog.get_default().get_port(&"suva").get_geo_position(), [] as Array[Vector2], &"nukualofa")
	t.check(route != null and route.is_ok(), "[chart] a route across the date line still plans (Suva to Nuku'alofa) %s" % (route.error if route else ""))
