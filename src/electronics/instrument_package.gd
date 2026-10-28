class_name InstrumentPackage
extends RefCounted
## Marine electronics (I026 stage 03): one of the three instrument packages
## a boat can carry, from data/electronics/instrument_packages.json.
##
##   classic             analogue dials and an LCD repeater (fitted to every
##                       boat, free)
##   modern_cruiser      compact displays with selectable pages
##   offshore_navigator  a multifunction display with layouts
##
## A package is a presentation: every one shows the same authoritative data
## (InstrumentData), so the cheap one is never less safe. What differs is
## the look (housing, screen, typography, illumination at night), the
## arrangement (`units`) and the pages or layouts on offer. The maker,
## SKERRY, is fictional.

const CATALOGUE_PATH := "res://data/electronics/instrument_packages.json"
const CLASSIC := "classic"
const MODERN := "modern_cruiser"
const OFFSHORE := "offshore_navigator"
const UNITS_DIALS := &"dials"
const UNITS_DISPLAYS := &"displays"
const UNITS_MFD := &"mfd"

static var _packages: Array[InstrumentPackage] = []
static var _brand := ""

var id := ""
var name := ""
var model := ""
var text := ""
var price := 0
var units: StringName = UNITS_DIALS
## The pages (or layouts) its displays can show, and what they show at first.
var pages: Array[String] = []
var default_pages: Array[String] = []
## The pages each display chooses from (display index -> pages); empty: all.
var slots: Array = []
## Real sizes in cm (about 1 deck unit each).
var cockpit_unit := 11.0
var plotter_size := Vector2(15, 10)
var _colours := {}


static func _load() -> void:
	if not _packages.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOGUE_PATH))
	var data: Dictionary = parsed if parsed is Dictionary else {}
	_brand = String(data.get("brand", ""))
	for entry: Variant in data.get("packages", []):
		if entry is Dictionary:
			_packages.append(_from_entry(entry))
	if _packages.is_empty():  # never without the free one
		_packages.append(_from_entry({"id": CLASSIC, "name": "Classic", "units": "dials", "pages": ["route"], "default_pages": ["route"]}))


static func _from_entry(entry: Dictionary) -> InstrumentPackage:
	var package := InstrumentPackage.new()
	package.id = String(entry.get("id", ""))
	package.name = String(entry.get("name", package.id))
	package.model = String(entry.get("model", ""))
	package.text = String(entry.get("text", ""))
	package.price = int(entry.get("price", 0))
	package.units = StringName(entry.get("units", "dials"))
	for page: Variant in entry.get("pages", []):
		package.pages.append(String(page))
	for page: Variant in entry.get("default_pages", []):
		package.default_pages.append(String(page))
	for slot: Variant in entry.get("slots", []):
		if slot is Array:
			var list: Array[String] = []
			for page: Variant in slot:
				if String(page) in package.pages:
					list.append(String(page))
			package.slots.append(list)
	package.cockpit_unit = float(entry.get("cockpit_unit", 11.0))
	var plotter: Array = entry.get("plotter", [15, 10])
	package.plotter_size = Vector2(float(plotter[0]), float(plotter[1])) if plotter.size() == 2 else Vector2(15, 10)
	for key: String in entry:
		var value: Variant = entry[key]
		if value is String and String(value).begins_with("#"):
			package._colours[key] = Color(String(value))
	return package


## Every package, cheapest first (as in the catalogue).
static func get_all() -> Array[InstrumentPackage]:
	_load()
	return _packages


static func get_ids() -> Array[String]:
	var ids: Array[String] = []
	for package in get_all():
		ids.append(package.id)
	return ids


## The package `id`, or null.
static func find(package_id: String) -> InstrumentPackage:
	for package in get_all():
		if package.id == package_id:
			return package
	return null


## The package `id`, or Classic when it is unknown.
static func get_package(package_id: String) -> InstrumentPackage:
	var package := find(package_id)
	return package if package else find(CLASSIC)


static func is_known(package_id: String) -> bool:
	return find(package_id) != null


## The (fictional) maker's name on the housings.
static func brand() -> String:
	_load()
	return _brand


## The pages display `index` can show (its slot, or all the pages).
func slot_pages(index: int) -> Array[String]:
	if index >= 0 and index < slots.size() and not (slots[index] as Array).is_empty():
		return slots[index]
	return pages


## The player-facing name and description (translated).
func get_display_name() -> String:
	return Loc.t(name)


func get_text() -> String:
	return Loc.t(text)


## A colour of the housing or screen. `role`: housing, housing_edge, screen,
## ink, accent, dial_face, dial_ink; with `night` the night variant where the
## package has one (red or dimmed illumination).
func colour(role: String, night := false) -> Color:
	if night and _colours.has(role + "_night"):
		return _colours[role + "_night"]
	return _colours.get(role, Color.MAGENTA)


## The colour between day and night (0 = day, 1 = night).
func colour_at(role: String, night_amount: float) -> Color:
	return colour(role, false).lerp(colour(role, true), clampf(night_amount, 0.0, 1.0))
