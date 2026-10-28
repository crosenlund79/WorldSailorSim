extends RefCounted
## Iteration 006, Checkpoints D and E: the harbour catalogue. Every harbour:
## a stable, unique id; a real position on the chart, on the coast (not
## inland, not out at sea); a harbour approach that reaches open water; a
## valid route to its nearest original harbour. Plus representative voyages
## (short coastal, island hopping, offshore, difficult coasts, narrow
## passages), the spatial lookup and search, and the original ids.

const ORIGINAL_IDS: Array[StringName] = [&"copenhagen", &"kiel", &"gothenburg", &"bergen", &"helsinki", &"portsmouth",
	&"dublin", &"brest", &"lisbon", &"gibraltar", &"barcelona", &"marseille", &"naples", &"piraeus", &"reykjavik"]
## The chart's extent: the whole world chart (Iteration 16; before, Europe's
## -25..37 °E, 33..72 °N).
const CHART := Rect2(-180.0, -72.0, 360.0, 152.0)
## A harbour must have land within this distance (nm): it lies on a coast.
const COAST_NM := 3.0
const REGIONS := ["baltic", "scandinavia", "north_sea", "british_isles", "channel", "biscay", "iberia_atlantic",
	"mediterranean", "adriatic", "ionian", "aegean", "north_atlantic", "levant",
	# Iteration 16: international harbours.
	"atlantic_islands", "caribbean", "central_america", "pacific",
	# I021: A Wider, Warmer World.
	"north_america", "west_africa", "south_atlantic", "indian_ocean", "southeast_asia"]

var t: Node
var catalog: PortCatalog
var router: SeaRouter


func run(runner: Node) -> void:
	t = runner
	catalog = PortCatalog.get_default()
	router = SeaRouter.get_default()
	_test_records()
	_test_positions()
	_test_routes_to_hubs()
	_test_representative_voyages()
	_test_spatial_lookup()
	_test_search()


func _test_records() -> void:
	var count := catalog.ports.size()
	t.check(count >= 150, "[harbours] %d harbours in the catalogue (target about 150)" % count)
	var ids := {}
	var problems: Array[String] = []
	var id_pattern := RegEx.create_from_string("^[a-z][a-z0-9_]*$")
	for port in catalog.ports:
		if ids.has(port.id):
			problems.append("duplicate %s" % port.id)
		ids[port.id] = true
		if id_pattern.search(String(port.id)) == null:
			problems.append("bad id %s" % port.id)
		if port.display_name.is_empty() or port.country.is_empty() or port.description.is_empty() or port.source.is_empty():
			problems.append("incomplete %s" % port.id)
		if port.importance < 1 or port.importance > 3 or port.region not in REGIONS:
			problems.append("importance/region %s" % port.id)
		if catalog.get_port(port.id) != port:
			problems.append("lookup %s" % port.id)
	t.check(problems.is_empty(), "[harbours] unique, well-formed ids; complete records; id lookup returns each (%s)" % [problems])
	t.check(ORIGINAL_IDS.all(func(id: StringName) -> bool: return catalog.has_port(id)), "[harbours] all 15 original harbour ids are kept")
	var names := {}
	var duplicates: Array[String] = []
	for port in catalog.ports:
		var key := "%s|%s" % [port.display_name.to_lower(), port.country]
		if names.has(key):
			duplicates.append(port.display_name)
		names[key] = true
	t.check(duplicates.is_empty(), "[harbours] no harbour is listed twice (%s)" % [duplicates])
	var by_region := {}
	for port in catalog.ports:
		by_region[port.region] = by_region.get(port.region, 0) + 1
	var spread := REGIONS.all(func(r: String) -> bool: return by_region.get(r, 0) >= 1)
	var largest: int = by_region.values().max()
	t.check(spread and largest <= count * 0.3, "[harbours] spread over every sea area, none above 30 %% (%s)" % [by_region])
	var islands := catalog.ports.filter(func(p: PortData) -> bool: return p.island).size()
	var major := catalog.ports.filter(func(p: PortData) -> bool: return p.importance == 1).size()
	t.check(islands >= 20 and major >= 15 and major <= 60, "[harbours] %d island harbours; %d major harbours shown at every zoom" % [islands, major])


func _test_positions() -> void:
	var outside: Array[String] = []
	var inland: Array[String] = []
	var offshore: Array[String] = []
	for port in catalog.ports:
		var geo := port.get_geo_position()
		if not CHART.has_point(geo):
			outside.append(String(port.id))
			continue
		if router.find_port_approach(port).is_empty():
			inland.append(String(port.id))
		# Colón and Panama City sit at the ends of the Panama passage, whose
		# channel (a gameplay abstraction) clears the cells around them.
		if not _land_within(geo, COAST_NM) and port.id not in [&"colon", &"panama_city"]:
			offshore.append(String(port.id))
	t.check(outside.is_empty(), "[harbours] every harbour lies within the chart (%s)" % [outside])
	t.check(inland.is_empty(), "[harbours] every harbour has an approach from open water: none inland or in a closed basin (%s)" % [inland])
	t.check(offshore.is_empty(), "[harbours] every harbour lies on a coast: land within %.0f nm (%s)" % [COAST_NM, offshore])


## Land on the finest chart at `geo` within `nm` (at least one and a half of
## that chart's cells: 7.5 nm on the 5 nm world chart).
func _land_within(geo: Vector2, nm: float) -> bool:
	var grid := router.grid.grid_at(geo)
	var cell_nm := 60.0 / grid.cells_per_degree
	nm = maxf(nm, 1.5 * cell_nm)
	var center := grid.geo_to_cell(geo)
	var r := ceili(nm / cell_nm * 1.2) + 1
	for y in range(floori(center.y) - r, floori(center.y) + r + 1):
		for x in range(floori(center.x) - r, floori(center.x) + r + 1):
			# On the coarse world chart an atoll or a small island is often only an
			# approach-only cell (land, but less than half of it).
			var land := grid.get_class_at(x, y) == NavGrid.LAND or (cell_nm > 1.5 and grid.get_class_at(x, y) == NavGrid.APPROACH)
			if land and GeoMath.distance_nm(geo, grid.cell_center_geo(x, y)) <= nm:
				return true
	return false


## Each added harbour to its nearest original harbour (and back is the same
## graph), so every one is connected to the network.
func _test_routes_to_hubs() -> void:
	var failures: Array[String] = []
	var longest := 0.0
	var started := Time.get_ticks_msec()
	for port in catalog.ports:
		if port.id in ORIGINAL_IDS:
			continue
		var hub := _nearest_original(port)
		var result := router.plan_route(port.id, port.get_geo_position(), [], hub)
		if not result.is_ok():
			failures.append("%s→%s: %s" % [port.id, hub, result.error])
		else:
			longest = maxf(longest, result.route.get_distance_nm())
	var elapsed := Time.get_ticks_msec() - started
	t.check(failures.is_empty(), "[routing] every added harbour has a valid sea route to its nearest original harbour (%s)" % [failures])
	print("    (routes to hubs: %d ms, longest %.0f nm)" % [elapsed, longest])


func _nearest_original(port: PortData) -> StringName:
	var best: StringName = ORIGINAL_IDS[0]
	var best_nm := INF
	for id in ORIGINAL_IDS:
		var nm := GeoMath.distance_nm(port.get_geo_position(), catalog.get_port(id).get_geo_position())
		if nm < best_nm:
			best_nm = nm
			best = id
	return best


func _test_representative_voyages() -> void:
	var trips := [
		["short coastal", &"aarhus", &"copenhagen", 0.0, 140.0],
		["short coastal", &"nice", &"cannes", 0.0, 30.0],
		["island hopping", &"mykonos", &"paros", 0.0, 40.0],
		["island hopping", &"palma", &"ibiza", 0.0, 120.0],
		["island hopping", &"hvar", &"korcula", 0.0, 60.0],
		["offshore", &"brest", &"a_coruna", 250.0, 400.0],
		["offshore", &"bergen", &"torshavn", 300.0, 500.0],
		["offshore", &"lisbon", &"cagliari", 800.0, 1300.0],
		["difficult coast", &"tromso", &"honningsvag", 0.0, 300.0],
		["difficult coast", &"arendal", &"kiel", 0.0, 400.0],
		["difficult coast", &"lerwick", &"kirkwall", 0.0, 150.0],
		["narrow passage", &"messina", &"catania", 0.0, 70.0],
		["narrow passage", &"bonifacio", &"olbia", 0.0, 80.0],
		["narrow passage (Strait of Gibraltar)", &"malaga", &"lagos", 150.0, 320.0],
		["narrow passage (Øresund)", &"malmo", &"copenhagen", 0.0, 40.0],
		["long", &"mariehamn", &"heraklion", 2500.0, 4500.0],
		["long", &"reykjavik", &"limassol", 3000.0, 6000.0],
	]
	for trip in trips:
		var from: StringName = trip[1]
		var to: StringName = trip[2]
		var result := router.plan_route(from, catalog.get_port(from).get_geo_position(), [], to)
		var nm := result.route.get_distance_nm() if result.is_ok() else 0.0
		var bounds_ok: bool = trip[4] <= 0.0 or (nm >= trip[3] and nm <= trip[4])
		t.check(result.is_ok() and bounds_ok and router.validate_route(result.route).is_empty(),
			"[routing] %s: %s → %s, %.0f nm %s" % [trip[0], from, to, nm, result.error])


func _test_spatial_lookup() -> void:
	# ports_in_rect agrees with a plain scan, for a few areas.
	var areas := [Rect2(10.0, 53.0, 6.0, 4.0), Rect2(22.0, 35.0, 6.0, 6.0), Rect2(-10.0, 35.0, 20.0, 10.0), CHART, Rect2(-24.0, 66.0, 1.0, 1.0)]
	var all_ok := true
	for area: Rect2 in areas:
		var fast := catalog.ports_in_rect(area).map(func(p: PortData) -> StringName: return p.id)
		var slow := catalog.ports.filter(func(p: PortData) -> bool: return area.has_point(p.get_geo_position())).map(
			func(p: PortData) -> StringName: return p.id)
		fast.sort()
		slow.sort()
		all_ok = all_ok and fast == slow
	t.check(all_ok, "[harbours] the spatial lookup finds exactly the harbours in an area")
	t.check_eq(catalog.ports_in_rect(CHART).size(), catalog.ports.size(), "[harbours] the whole chart holds every harbour")


func _test_search() -> void:
	var split := catalog.search("spl")
	t.check(not split.is_empty() and split[0].id == &"split", "[search] 'spl' finds Split first")
	var greece := catalog.search("greece", 50)
	t.check(greece.size() >= 15 and greece.all(func(p: PortData) -> bool: return p.country == "Greece"), "[search] 'greece' lists Greek harbours (%d)" % greece.size())
	t.check(catalog.search("malm")[0].id == &"malmo", "[search] 'malm' finds Malmö (diacritics in the name)")
	t.check(catalog.search("").is_empty() and catalog.search("zzzz").is_empty(), "[search] nothing for an empty or unknown query")
	t.check(catalog.search("a", 8).size() == 8, "[search] results are limited")
