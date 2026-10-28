class_name InstrumentState
extends RefCounted
## Marine electronics (I026 stage 03): the instrument packages the Captain
## owns and which one is fitted to each boat. Saved as the optional
## "instruments" section (format 12 unchanged):
##
##   owned   ids of packages bought (InstrumentPackage); Classic is always
##           owned and is never listed. They are the Captain's: once bought,
##           a package can be fitted to any boat of the fleet, and it is
##           never lost (changing boats or packages takes nothing away).
##   fitted  by vessel id (String): the package fitted to that boat. A boat
##           without an entry has Classic.
##   pages   by package id: the page (or layout) each of its displays shows,
##           e.g. {"modern_cruiser": ["speed", "wind", "route"]}. A
##           preference; unknown pages fall back to the package's defaults.
##
## Never refuses a save: an older save has no section (Classic everywhere,
## nothing owned); unknown or malformed parts are left out quietly.

var owned: Array[String] = []
var fitted := {}
var pages := {}


func duplicate_state() -> InstrumentState:
	var copy := InstrumentState.new()
	copy.owned = owned.duplicate()
	copy.fitted = fitted.duplicate()
	copy.pages = pages.duplicate(true)
	return copy


func owns(package_id: String) -> bool:
	return package_id == InstrumentPackage.CLASSIC or package_id in owned


## The ids the Captain can fit: Classic and every package bought.
func owned_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in InstrumentPackage.get_ids():
		if owns(id):
			ids.append(id)
	return ids


func add_owned(package_id: String) -> void:
	if package_id != InstrumentPackage.CLASSIC and InstrumentPackage.is_known(package_id) and not package_id in owned:
		owned.append(package_id)


## The package fitted to `vessel_id` (Classic by default).
func get_fitted(vessel_id: StringName) -> String:
	var id := String(fitted.get(String(vessel_id), InstrumentPackage.CLASSIC))
	return id if owns(id) and InstrumentPackage.is_known(id) else InstrumentPackage.CLASSIC


func set_fitted(vessel_id: StringName, package_id: String) -> void:
	if package_id == InstrumentPackage.CLASSIC:
		fitted.erase(String(vessel_id))
	else:
		fitted[String(vessel_id)] = package_id


## The pages `package` shows now (one per display; its defaults at first).
func get_pages(package: InstrumentPackage) -> Array[String]:
	var chosen: Array[String] = package.default_pages.duplicate()
	var saved: Variant = pages.get(package.id)
	if saved is Array:
		for i in mini((saved as Array).size(), chosen.size()):
			if String(saved[i]) in package.slot_pages(i):
				chosen[i] = String(saved[i])
	return chosen


func set_page(package: InstrumentPackage, display: int, page: String) -> void:
	var chosen := get_pages(package)
	if display < 0 or display >= chosen.size() or not page in package.slot_pages(display):
		return
	chosen[display] = page
	pages[package.id] = Array(chosen)


func is_default() -> bool:
	return owned.is_empty() and fitted.is_empty() and pages.is_empty()


func to_dict() -> Dictionary:
	return {"owned": owned.duplicate(), "fitted": fitted.duplicate(), "pages": pages.duplicate(true)}


## Never fails: unknown ids and malformed parts are dropped.
static func from_dict(data: Variant) -> InstrumentState:
	var state := InstrumentState.new()
	if not data is Dictionary:
		return state
	var saved_owned: Variant = data.get("owned", [])
	if saved_owned is Array:
		for id: Variant in saved_owned:
			if id is String:
				state.add_owned(id)
	var saved_fitted: Variant = data.get("fitted", {})
	if saved_fitted is Dictionary:
		for vessel_id: Variant in saved_fitted:
			var id: Variant = saved_fitted[vessel_id]
			if vessel_id is String and id is String and state.owns(id) and InstrumentPackage.is_known(id) and id != InstrumentPackage.CLASSIC:
				state.fitted[vessel_id] = id
	var saved_pages: Variant = data.get("pages", {})
	if saved_pages is Dictionary:
		for id: Variant in saved_pages:
			var package := InstrumentPackage.find(String(id)) if id is String else null
			var list: Variant = saved_pages[id]
			if package and list is Array:
				var clean: Array = []
				for page: Variant in list:
					clean.append(String(page) if page is String and String(page) in package.pages else "")
				state.pages[package.id] = clean
	return state
