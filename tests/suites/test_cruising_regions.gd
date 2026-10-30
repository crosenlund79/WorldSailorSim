extends RefCounted
## Regions and Harbours 2026: the Detailed Cruising Regions (Denmark's Home
## Waters, Sweden's Archipelagos, New Zealand's Long White Cloud). Their
## registry and texts; which harbours belong; the destinations (classes,
## facilities, metadata for I028); every named anchorage passes the game's
## anchoring rule; the detailed Swedish and New Zealand charts; representative
## voyages, among them archipelago passages and stops at a named anchorage;
## the chart's marks, legend, one-time hint and planning via an anchorage;
## and the regional waterfront looks.

const APP_SCENE := preload("res://src/app/app.tscn")
const INFO := {
	&"denmark": "Discover a rich network of island harbours, sheltered passages and welcoming coastal communities.",
	&"sweden": "Explore winding archipelagos, island villages and quiet anchorages along Sweden's remarkable coastline.",
	&"new_zealand": "Discover sheltered bays, remote anchorages and memorable coastal passages across New Zealand's two main islands.",
}
## Voyages: [from, to, what it exercises].
const VOYAGES := [
	[&"svendborg", &"lyo", "South Funen Archipelago: Svendborg to Lyø"],
	[&"copenhagen", &"christianso", "Øresund and the Baltic to Christiansø"],
	[&"vaxholm", &"sandhamn", "Stockholm archipelago: Vaxholm to Sandhamn"],
	[&"marstrand", &"smogen", "Bohuslän: Marstrand to Smögen inside the skerries"],
	[&"nynashamn", &"arkosund", "the Swedish east coast: Nynäshamn to Arkösund"],
	[&"auckland", &"opua", "Hauraki Gulf to the Bay of Islands"],
	[&"picton", &"wellington", "across Cook Strait"],
	[&"bluff", &"halfmoon_bay", "Foveaux Strait to Stewart Island"],
	[&"tauranga", &"whitianga", "Bay of Plenty to the Coromandel"],
]
## Voyages with a stop at a named anchorage: [from, anchorage, to].
const ANCHORAGE_VOYAGES := [
	[&"vaxholm", &"grinda_hastholmssundet", &"finnhamn"],
	[&"svendborg", &"lyo_west_bay", &"lyo"],
	[&"paihia", &"roberton_island", &"russell"],
	[&"nelson", &"torrent_bay", &"port_motueka"],
]

var t: Node
var regions: CruisingRegions
var catalog: PortCatalog
var router: SeaRouter


func run(runner: Node) -> void:
	t = runner
	regions = CruisingRegions.get_default()
	catalog = PortCatalog.get_default()
	router = SeaRouter.get_default()
	_test_registry()
	_test_membership()
	_test_destinations()
	_test_charts()
	_test_voyages()
	_test_looks()
	await _test_chart_presentation()


func _test_registry() -> void:
	t.check_eq(regions.regions.size(), 3, "[cruising] three Detailed Cruising Regions")
	for id: StringName in INFO:
		var region := regions.get_region(id)
		t.check_eq(region.get("description", ""), INFO[id], "[cruising] %s's info text is the commissioned one" % id)
	t.check_eq(regions.get_region(&"denmark").title, "Denmark — Home Waters", "[cruising] Denmark is Home Waters")
	t.check_eq(regions.get_region(&"sweden").title, "Sweden — The Archipelagos", "[cruising] Sweden is The Archipelagos")
	t.check_eq(regions.get_region(&"new_zealand").title, "New Zealand — The Long White Cloud", "[cruising] New Zealand is The Long White Cloud")
	t.check_eq(regions.legend, "An area with more local harbours, anchorages and coastal destinations to explore.", "[cruising] the legend text")
	t.check(regions.hint.begins_with("Explore the world at your own pace.") and regions.hint.ends_with("Detailed Cruising Regions."),
		"[cruising] the one-time hint text")
	var unfinished := false
	for region in regions.regions:
		for text: String in [region.name, region.title, region.description]:
			unfinished = unfinished or text.to_lower().contains("unfinished") or text.to_lower().contains("incomplete")
	t.check(not unfinished, "[cruising] nothing calls any part of the world unfinished")
	SettingsManager.set_language(&"da")
	var danish := Loc.t(INFO[&"denmark"]) != INFO[&"denmark"] and Loc.t(regions.legend) != regions.legend and Loc.t(regions.hint) != regions.hint
	SettingsManager.set_language(&"en")
	t.check(danish, "[cruising] the info, legend and hint are in Danish too")


func _test_membership() -> void:
	var expect := {&"copenhagen": &"denmark", &"lyo": &"denmark", &"christianso": &"denmark", &"skagen": &"denmark",
		&"gothenburg": &"sweden", &"vaxholm": &"sweden", &"kyrkbacken": &"sweden", &"visby": &"sweden",
		&"auckland": &"new_zealand", &"halfmoon_bay": &"new_zealand", &"milford_deepwater_basin": &"new_zealand",
		&"lulea": &"", &"sundsvall": &"", &"bergen": &"", &"kiel": &"", &"papeete": &""}
	var wrong: Array[String] = []
	for id: StringName in expect:
		var got := regions.region_of_port(catalog.get_port(id))
		if got != expect[id]:
			wrong.append("%s: %s" % [id, got])
	t.check(wrong.is_empty(), "[cruising] harbours belong to their country's region by its outline, Luleå and Bergen to none (%s)" % [wrong])
	var counts := {}
	for port in catalog.ports:
		var region := regions.region_of_port(port)
		if region != &"":
			counts[region] = counts.get(region, 0) + 1
	print("    harbours per Detailed Cruising Region: %s" % counts)
	t.check(counts.get(&"denmark", 0) >= 75 and counts.get(&"sweden", 0) >= 55 and counts.get(&"new_zealand", 0) >= 35,
		"[cruising] each region has many more harbours than before (%s)" % counts)


func _test_destinations() -> void:
	var problems: Array[String] = []
	var anchorages := 0
	var classes := {}
	for record: Dictionary in regions.destinations.values():
		var id: StringName = record.id
		classes[record["class"]] = classes.get(record["class"], 0) + 1
		for key in ["country", "cruising_region", "latitude", "longitude", "overnight", "scenic", "services", "vessel_note", "source"]:
			if not record.has(key):
				problems.append("%s lacks %s" % [id, key])
		if regions.get_region(record.cruising_region).is_empty():
			problems.append("%s: no region %s" % [id, record.cruising_region])
		if record["class"] == CruisingRegions.CLASS_ANCHORAGE:
			anchorages += 1
			if catalog.has_port(id):
				problems.append("%s: an anchorage is not a harbour" % id)
			if not (record.services as Array).is_empty():
				problems.append("%s: an anchorage has no shore services" % id)
			var onward := catalog.get_port(StringName(record.get("onward", "")))
			if onward == null:
				problems.append("%s: no onward harbour" % id)
			elif GeoMath.distance_nm(record.position, onward.get_geo_position()) > 40.0:
				problems.append("%s: onward harbour %.0f nm away" % [id, GeoMath.distance_nm(record.position, onward.get_geo_position())])
			if not GameSession.anchorage_spot(record.position).ok:
				problems.append("%s: not an anchorage by the game's rule" % id)
		else:
			var port := catalog.get_port(id)
			if port == null:
				problems.append("%s: not in the harbour catalogue" % id)
				continue
			if regions.region_of_port(port) != record.cruising_region:
				problems.append("%s: outside its region's outline" % id)
			var facilities := HarbourFacilities.for_port(id)
			var full: bool = record["class"] == CruisingRegions.CLASS_HARBOUR
			if facilities.haul_out != full or (full and not facilities.boatyard) or not facilities.go_ashore:
				problems.append("%s: facilities do not match its class" % id)
	t.check(problems.is_empty(), "[cruising] every destination is complete, harbours are in the catalogue with facilities by class, anchorages pass the anchoring rule with an onward harbour (%s)" % [problems])
	t.check(anchorages >= 45 and classes.get(CruisingRegions.CLASS_HARBOUR, 0) >= 40 and classes.get(CruisingRegions.CLASS_GUEST_HARBOUR, 0) >= 40
		and classes.get(CruisingRegions.CLASS_FISHING_VILLAGE, 0) >= 25, "[cruising] destinations by class: %s" % classes)
	t.check_eq(regions.class_of(&"copenhagen"), CruisingRegions.CLASS_HARBOUR, "[cruising] a harbour of the main catalogue counts as a harbour")
	t.check_eq(regions.class_of(&"lyo"), CruisingRegions.CLASS_GUEST_HARBOUR, "[cruising] Lyø is a guest harbour")
	var in_denmark := regions.destinations_in(&"denmark")
	t.check(in_denmark.any(func(d: Dictionary) -> bool: return d.id == &"copenhagen") and in_denmark.any(func(d: Dictionary) -> bool: return d.id == &"dyreborg"),
		"[cruising] a region's destinations include its older harbours and the new ones (%d in Denmark)" % in_denmark.size())


func _test_charts() -> void:
	var expect := {&"vaxholm": "swedish_east_coast", &"smogen": "bohuslan", &"opua": "nz_north", &"picton": "nz_north",
		&"halfmoon_bay": "nz_south", &"lyo": "denmark", &"visby": "swedish_east_coast"}
	var wrong: Array[String] = []
	for id: StringName in expect:
		var got := router.grid.region_id_at(catalog.get_port(id).get_geo_position())
		if got != expect[id]:
			wrong.append("%s: %s" % [id, got])
	t.check(wrong.is_empty(), "[cruising] the Swedish and New Zealand detailed charts cover their harbours (%s)" % [wrong])
	var nz := router.grid.child_at(catalog.get_port(&"opua").get_geo_position())
	t.check(nz.region_id == "nz_north" and nz.factor == 18 and nz.cells_per_degree == 216.0,
		"[cruising] New Zealand's chart refines the world chart 18 times (%s, %d)" % [nz.region_id, nz.factor])
	var rects: Array[Rect2] = []
	for grid in router.grid.all_grids():
		if grid.region_id in ["denmark", "bohuslan", "swedish_east_coast"]:
			rects.append(grid.get_base_rect())
	var overlap := false
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			overlap = overlap or rects[i].intersects(rects[j])
	t.check(not overlap, "[cruising] the European detail charts do not overlap")


func _test_voyages() -> void:
	for voyage: Array in VOYAGES:
		var from := catalog.get_port(voyage[0])
		var result := router.plan_route(from.id, from.get_geo_position(), [], voyage[1])
		if t.check(result.is_ok(), "[cruising] %s (%s)" % [voyage[2], result.error if not result.is_ok() else "%.0f nm" % result.route.get_distance_nm()]):
			t.check(router.validate_route(result.route).is_empty(), "[cruising]   its route is valid on the detailed chart")
	for voyage: Array in ANCHORAGE_VOYAGES:
		var from := catalog.get_port(voyage[0])
		var anchorage := regions.get_anchorage(voyage[1])
		var waypoints: Array[Vector2] = [anchorage.position]
		var result := router.plan_route(from.id, from.get_geo_position(), waypoints, voyage[2])
		t.check(result.is_ok(), "[cruising] %s to %s, anchoring at %s on the way (%s)" % [voyage[0], voyage[2], anchorage.name,
			result.error if not result.is_ok() else "%.1f nm" % result.route.get_distance_nm()])


func _test_looks() -> void:
	t.check_eq(HarbourDressing.town_for(&"lyo"), &"danish", "[cruising] a Danish harbour gets the Danish waterfront")
	t.check_eq(HarbourDressing.town_for(&"vaxholm"), &"swedish", "[cruising] a Swedish harbour gets the Swedish waterfront")
	t.check_eq(HarbourDressing.town_for(&"picton"), &"new_zealand", "[cruising] a New Zealand harbour gets its own waterfront")
	t.check_eq(HarbourDressing.town_for(&"piraeus"), HarbourDressing.archetype_for(&"piraeus"), "[cruising] elsewhere the archetype's town is unchanged")
	t.check_eq(HarbourDressing.archetype_for(&"picton"), HarbourDressing.ARCHETYPE_TROPICAL,
		"[cruising] the economy's archetype is unchanged (prices and hours do not move)")


func _test_chart_presentation() -> void:
	Simulation.auto_advance = false
	var app: Node = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	app.start_new_game()
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	var state := GameSession.get_state_snapshot()
	state.location_id = &"vaxholm"
	state.vessel_status = SessionState.STATUS_MOORED
	state.vessel_position = catalog.get_port(&"vaxholm").get_geo_position()
	state.voyage = null
	GameSession.replace_state(state)
	app.open_chart()
	await t.wait_until(func() -> bool: return app.router.current_screen is WorldMap and not app.router.is_busy(), 10.0)
	var map := app.router.current_screen as WorldMap
	if not t.check(map != null, "[cruising] the chart opens"):
		app.queue_free()
		return
	var view := map.get_map_view()
	t.check(map.get_course_status_text().contains("Detailed Cruising Regions"), "[cruising] the first chart opening shows the one-time hint")
	view.center_on_geo(Vector2(15.0, 57.0), 20.0 / view.units_per_degree)
	await t.frames(3)
	t.check(view.cruising_mark_strength() > 0.9 and map.is_cruising_legend_shown(), "[cruising] zoomed out: the regions' marks and the legend show")
	view.hovered_cruising_region = &"sweden"
	map._update_cruising_tooltip()
	t.check(map.get_cruising_info_text().contains(INFO[&"sweden"]), "[cruising] a region's mark explains it")
	view.hovered_cruising_region = &""
	view.center_on_geo(Vector2(18.6, 59.42), 400.0 / view.units_per_degree)
	await t.frames(3)
	t.check(view.cruising_mark_strength() == 0.0 and not map.is_cruising_legend_shown(), "[cruising] zoomed in: the marks give way to the harbours")
	t.check(view.get_shown_anchorage_ids().has(&"grinda_hastholmssundet"), "[cruising] zoomed in: the named anchorages have markers")
	t.check_eq(map.plan_via_anchorage(&"grinda_hastholmssundet"), "", "[cruising] a named anchorage can be chosen on the chart")
	t.check(map.get_draft_anchorages() == [true] and map.get_draft_route() != null and map.get_draft_route().destination_port_id == &"vaxholm",
		"[cruising]   the course goes to its harbour, anchoring there on the way")
	t.check_eq(map.apply_course(), "", "[cruising]   the course can be applied")
	var planned := GameSession.get_planned_route()
	t.check(planned != null and planned.is_anchorage(0), "[cruising]   the planned route keeps the anchorage stop")
	app.open_chart()
	await t.wait_until(func() -> bool: return app.router.current_screen is WorldMap and not app.router.is_busy(), 5.0)
	t.check(not (app.router.current_screen as WorldMap).get_course_status_text().contains("Detailed Cruising Regions"),
		"[cruising] the hint is shown only once")
	app.queue_free()
	Simulation.auto_advance = true
	await t.frames(2)

