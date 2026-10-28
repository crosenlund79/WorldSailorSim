class_name HarbourLooks
extends RefCounted
## What a harbour looks like beyond the guest pontoon (I021): each harbour's
## look is chosen in data/harbours/harbour_looks.json, by what the place looks
## like (its buildings, materials, land and climate), never by the continent
## alone. A Danish fishing harbour and a New Zealand harbour may share the
## timber look; Willemstad's gabled waterfront looks Dutch.
##
## Two kinds of art:
## - a look (an archetype): one illustration shared by every harbour given it;
## - a harbour's own art (HarbourArt, data/harbours/<id>.tres): landmarks drawn
##   for that place alone. Those harbours are the special harbours, marked on
##   the chart with the reason in "special" (a test keeps the two in step).
##
## Loaded once; the archetype art is built on first use and kept (a handful of
## small resources, one texture each, loaded lazily), so repeated visits cost
## nothing new.

const DATA_PATH := "res://data/harbours/harbour_looks.json"
## A look's illustration is drawn like a landmark: centred this far beyond the
## pontoon, this wide (the Nyhavn strip's placement).
const OFFSET := Vector2(0, 79)
const WIDTH := 1150.0

static var _default: HarbourLooks

## look id -> {"title", "texture"}
var looks := {}
## port id -> look id
var harbours := {}
## port id -> {"text": why it is special} (English; shown translated)
var special := {}
var _art_cache := {}


static func get_default() -> HarbourLooks:
	if _default == null:
		_default = HarbourLooks.new()
		_default.load_data(DATA_PATH)
	return _default


func load_data(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(text) if text != "" else null
	if not data is Dictionary:
		push_warning("Harbour looks: %s could not be read; every harbour shows the generic quay." % path)
		return
	looks = data.get("looks", {})
	harbours = data.get("harbours", {})
	special = data.get("special", {})


## The look id of a harbour ("" when it has none: the generic quay only).
func look_of(port_id: StringName) -> StringName:
	return StringName(harbours.get(String(port_id), ""))


## The look's name in the current language ("Nordic timber harbour"), or "".
func look_title(look: StringName) -> String:
	var entry: Dictionary = looks.get(String(look), {})
	return Loc.t(String(entry.get("title", ""))) if not entry.is_empty() else ""


func is_special(port_id: StringName) -> bool:
	return special.has(String(port_id))


## Why a harbour is special, in the current language ("" when it is not).
func special_note(port_id: StringName) -> String:
	if not is_special(port_id):
		return ""
	return Loc.t(String((special[String(port_id)] as Dictionary).get("text", "")))


## The art drawn beyond the pontoon: the harbour's own (HarbourArt with
## landmarks), else its look's illustration, else null (the generic quay).
func art_for(port_id: StringName) -> HarbourArt:
	if port_id.is_empty():
		return null
	var own := HarbourArt.for_port(port_id)
	if own and not own.get_landmarks().is_empty():
		return own
	var look := look_of(port_id)
	if look.is_empty():
		return own
	var art := _look_art(look)
	if art == null:
		return own
	if own:  # a harbour file without landmarks (e.g. only its atmosphere): keep that, add the look
		var merged := own.duplicate() as HarbourArt
		merged.landmarks = art.landmarks
		return merged
	return art


## The look's illustration as HarbourArt (shared, built once), or null when its
## image is missing (the harbour then shows the generic quay).
func _look_art(look: StringName) -> HarbourArt:
	if _art_cache.has(look):
		return _art_cache[look]
	var entry: Dictionary = looks.get(String(look), {})
	var path := String(entry.get("texture", ""))
	var art: HarbourArt = null
	if path != "" and ResourceLoader.exists(path):
		var texture := load(path) as Texture2D
		if texture:
			var landmark := HarbourLandmark.new()
			landmark.title = String(entry.get("title", look))
			landmark.texture = texture
			landmark.offset = OFFSET
			landmark.width = WIDTH
			art = HarbourArt.new()
			art.landmarks.append(landmark)
	if art == null:
		push_warning("Harbour look '%s' has no image (%s); the generic quay is shown." % [look, path])
	_art_cache[look] = art
	return art


## The picture for the arrival card: the harbour's own landmark or its look's
## illustration (null when it has neither).
func picture_for(port_id: StringName) -> Texture2D:
	var art := art_for(port_id)
	if art == null:
		return null
	var landmarks := art.get_landmarks()
	return landmarks[0].texture if not landmarks.is_empty() else null
