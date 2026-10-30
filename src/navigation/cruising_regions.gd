class_name CruisingRegions
extends RefCounted
## The Detailed Cruising Regions (Regions and Harbours 2026): areas of the
## world with more local harbours, anchorages and coastal destinations to
## explore (Denmark's Home Waters, Sweden's Archipelagos, New Zealand's Long
## White Cloud). Data only: data/cruising/regions.json defines each region
## (its names, info text, outlines, chart mark and waterfront look) and
## data/cruising/destinations.json each destination in them, built by
## tools/navigation/build_cruising.py.
##
## Harbours stay ordinary PortData (PortCatalog): this adds what a harbour is
## (full-service harbour, guest harbour, fishing village), its services,
## overnight suitability, scenic tags and vessel notes, for the passenger
## work of I028. Natural anchorages are destinations of their own: a name, a
## position the game's anchoring rule accepts, a description and the harbour
## to sail on to. They have no shore facilities and are never moored at.
##
## A harbour belongs to a region when its country is the region's and it lies
## inside one of the region's outlines (a harbour of the region's country
## elsewhere, such as Luleå, does not). More regions are more entries in the
## JSON: nothing here names one.

const REGIONS_PATH := "res://data/cruising/regions.json"
const DESTINATIONS_PATH := "res://data/cruising/destinations.json"
const CLASS_HARBOUR := &"harbour"
const CLASS_GUEST_HARBOUR := &"guest_harbour"
const CLASS_FISHING_VILLAGE := &"fishing_village"
const CLASS_ANCHORAGE := &"anchorage"
## Player-facing names of the classes (gettext keys).
const CLASS_NAMES := {CLASS_HARBOUR: "Harbour", CLASS_GUEST_HARBOUR: "Guest harbour",
	CLASS_FISHING_VILLAGE: "Fishing village", CLASS_ANCHORAGE: "Natural anchorage"}

static var _default: CruisingRegions

## [{"id", "name", "title", "country", "description", "look", "chart_regions",
## "symbol" (Vector2 geo), "outlines" (Array[PackedVector2Array] geo)}]
var regions: Array[Dictionary] = []
## Destination id -> its record (see build_cruising.py); anchorages also in `anchorages`.
var destinations := {}
var anchorages: Array[Dictionary] = []
var legend := ""
var hint := ""
var _region_of_port := {}


static func get_default() -> CruisingRegions:
	if _default == null:
		_default = CruisingRegions.new()
		_default.load_files(REGIONS_PATH, DESTINATIONS_PATH)
	return _default


func load_files(regions_path: String, destinations_path: String) -> void:
	regions.clear()
	destinations.clear()
	anchorages.clear()
	_region_of_port.clear()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(regions_path)) if FileAccess.file_exists(regions_path) else null
	if data is Dictionary:
		legend = String(data.get("legend", ""))
		hint = String(data.get("hint", ""))
		for entry: Dictionary in data.get("regions", []):
			var outlines: Array[PackedVector2Array] = []
			for ring: Array in entry.get("outlines", []):
				var points := PackedVector2Array()
				for p: Array in ring:
					points.append(Vector2(float(p[0]), float(p[1])))
				outlines.append(points)
			var symbol: Array = entry.get("symbol", [0.0, 0.0])
			regions.append({"id": StringName(entry.id), "name": String(entry.get("name", "")), "title": String(entry.get("title", "")),
				"country": String(entry.get("country", "")), "description": String(entry.get("description", "")),
				"look": StringName(entry.get("look", "")), "chart_regions": entry.get("chart_regions", []),
				"symbol": Vector2(float(symbol[0]), float(symbol[1])), "outlines": outlines})
	var list: Variant = JSON.parse_string(FileAccess.get_file_as_string(destinations_path)) if FileAccess.file_exists(destinations_path) else null
	if list is Dictionary:
		for entry: Dictionary in list.get("destinations", []):
			var record := entry.duplicate()
			record.id = StringName(entry.id)
			record["class"] = StringName(entry.get("class", ""))
			record.cruising_region = StringName(entry.get("cruising_region", ""))
			record["position"] = Vector2(float(entry.longitude), float(entry.latitude))
			destinations[record.id] = record
			if record["class"] == CLASS_ANCHORAGE:
				anchorages.append(record)


func get_region(id: StringName) -> Dictionary:
	for region in regions:
		if region.id == id:
			return region
	return {}


## The Detailed Cruising Region (id) a harbour belongs to, or &"".
func region_of_port(port: PortData) -> StringName:
	if port == null:
		return &""
	if not _region_of_port.has(port.id):
		_region_of_port[port.id] = region_at(port.get_geo_position(), port.country)
	return _region_of_port[port.id]


func is_detailed(port: PortData) -> bool:
	return region_of_port(port) != &""


## The region whose outline holds `geo` (and whose country is `country`, if given).
func region_at(geo: Vector2, country := "") -> StringName:
	for region in regions:
		if not country.is_empty() and region.country != country:
			continue
		for outline: PackedVector2Array in region.outlines:
			if Geometry2D.is_point_in_polygon(geo, outline):
				return region.id
	return &""


## The destination record of a harbour or anchorage, or {} (a harbour of the
## main catalogue has none: it is a harbour with the services of its facilities).
func get_destination(id: StringName) -> Dictionary:
	return destinations.get(id, {})


## A destination's class (CLASS_*): from its record, else "harbour" for any
## harbour of the catalogue.
func class_of(id: StringName) -> StringName:
	var record := get_destination(id)
	return record.get("class", CLASS_HARBOUR) if not record.is_empty() else CLASS_HARBOUR


func get_anchorage(id: StringName) -> Dictionary:
	var record := get_destination(id)
	return record if record.get("class", &"") == CLASS_ANCHORAGE else {}


## Every destination of a region: its harbours (records of the catalogue's
## harbours inside it included, as {"id", "class": harbour}) and anchorages.
func destinations_in(region_id: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen := {}
	for record: Dictionary in destinations.values():
		if record.cruising_region == region_id:
			result.append(record)
			seen[record.id] = true
	for port in PortCatalog.get_default().ports:
		if not seen.has(port.id) and region_of_port(port) == region_id:
			result.append({"id": port.id, "class": CLASS_HARBOUR, "cruising_region": region_id, "position": port.get_geo_position()})
	return result


## Anchorages inside a geographic rectangle (chart drawing).
func anchorages_in_rect(area: Rect2) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record in anchorages:
		if area.has_point(record.position):
			result.append(record)
	return result


## The waterfront palette of a harbour (HarbourDressing.TOWNS): its region's
## look, or &"" outside the Detailed Cruising Regions.
func look_for(port_id: StringName) -> StringName:
	var port := PortCatalog.get_default().get_port(port_id) if not port_id.is_empty() else null
	var region := get_region(region_of_port(port))
	return region.get("look", &"")


## The class's name in the current language.
static func class_name_of(destination_class: StringName) -> String:
	return Loc.t(String(CLASS_NAMES.get(destination_class, "Harbour")))
