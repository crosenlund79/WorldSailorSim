class_name Pastimes
extends RefCounted
## The captain's pastimes aboard (I022): Postcards from the Sea and A Game
## Developer at Sea. The data (data/pastimes/postcards.json, game_dev.json)
## and the rules that read the game's own records; GameSession keeps the
## state (PastimesState) and App spends the time (the one clock).
##
## Postcards: the subjects are real - harbours visited (Captain's Log), fish
## caught (FishingState records), the companion, voyages and the weather met
## on them (log records), and the evening light where the boat is when the
## sun is low. Each subject earns renown once (ObjectiveProgress, key
## "postcard:<kind>:<subject>"); a postcard of the same subject again is a
## memory, not a reward.

const POSTCARDS_PATH := "res://data/pastimes/postcards.json"
const GAME_PATH := "res://data/pastimes/game_dev.json"
const KINDS: Array[String] = ["harbour", "fish", "companion", "voyage", "weather", "sunset"]
const LAYOUTS: Array[String] = ["classic", "snapshot", "banner"]
## The sun counts as low (evening or morning light) between these elevations.
const LOW_SUN := Vector2(-8.0, 12.0)

static var _postcards := {}
static var _game := {}


static func _load(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func postcard_data() -> Dictionary:
	if _postcards.is_empty():
		_postcards = _load(POSTCARDS_PATH)
	return _postcards


static func game_data() -> Dictionary:
	if _game.is_empty():
		_game = _load(GAME_PATH)
	return _game


# --- Postcards ----------------------------------------------------------------------------------

static func postcard_minutes() -> float:
	return float(postcard_data().get("minutes", 120))


static func postcard_renown() -> int:
	return int(postcard_data().get("renown", 3))


static func kind_name(kind: String) -> String:
	return Loc.t(String((postcard_data().get("kinds", {}) as Dictionary).get(kind, {}).get("name", kind)))


static func layout_name(layout: String) -> String:
	return Loc.t(String((postcard_data().get("layouts", {}) as Dictionary).get(layout, {}).get("name", layout)))


static func captions(kind: String) -> Array:
	return (postcard_data().get("kinds", {}) as Dictionary).get(kind, {}).get("captions", [])


## The postcards that can be made now, from the game's own records:
## [{"kind", "subject", "title", "args"}] (args fill the caption's %s).
static func subjects() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var catalog := PortCatalog.get_default()
	var log := GameSession.get_captains_log()
	for id: StringName in log.get_visited_ids():
		var name := catalog.get_display_name(id)
		out.append({"kind": "harbour", "subject": String(id), "title": name, "args": [name]})
	var fishing := GameSession.get_fishing()
	for species: String in fishing.records:
		var fish_name := FishingCatalog.get_default().get_species_name(species)
		out.append({"kind": "fish", "subject": species, "title": fish_name, "args": [fish_name.to_lower()]})
	var kind := GameSession.get_companion().kind
	out.append({"kind": "companion", "subject": String(kind), "title": CompanionState.display_name(kind), "args": []})
	var seen := {}
	for record: Dictionary in log.voyages:
		if record.get("outcome") != String(CaptainsLog.OUTCOME_ARRIVED):
			continue
		var key := "%s-%s" % [record.from, record.to]
		if seen.has(key):
			continue
		seen[key] = true
		var from := catalog.get_display_name(StringName(record.from))
		var to := catalog.get_display_name(StringName(record.to))
		out.append({"kind": "voyage", "subject": key, "title": "%s → %s" % [from, to], "args": [from, to]})
		var hazard := int(record.get("worst_hazard", 0))
		if hazard > 0:
			var weather := weather_name(hazard)
			out.append({"kind": "weather", "subject": "%s:%d" % [key, hazard], "title": "%s (%s → %s)" % [weather.capitalize(), from, to],
				"args": [weather]})
	var elevation := Daylight.sun_elevation(GameSession.get_vessel_position(), GameSession.get_game_time())
	if elevation > LOW_SUN.x and elevation < LOW_SUN.y:
		var place := where_now()
		out.append({"kind": "sunset", "subject": place, "title": place, "args": [place]})
	return out


## "rough weather", "heavy weather", "a storm" (WeatherModel hazard levels).
static func weather_name(hazard: int) -> String:
	return Loc.t(String((postcard_data().get("weather_names", {}) as Dictionary).get(str(clampi(hazard, 1, 3)), "rough weather")))


## The harbour the boat lies in, or the sea near the nearest one.
static func where_now() -> String:
	if not GameSession.is_underway() and GameSession.get_location():
		return GameSession.get_location().display_name
	var place := HatStory.describe_place(GameSession.get_vessel_position(), &"")
	return String(place.get("text", "")) if not String(place.get("text", "")).is_empty() else Loc.t("at sea")


## The caption text of `card` (a draft or a scrapbook entry) in the current
## language; `args` are the subject's names.
static func caption_text(kind: String, caption: int, args: Array) -> String:
	var list := captions(kind)
	if list.is_empty():
		return ""
	var template := Loc.t(String(list[clampi(caption, 0, list.size() - 1)]))
	return template % args if template.count("%s") == args.size() else template


## The names a subject's caption needs (its %s), in the current language:
## for a scrapbook card made long ago as much as for a new one.
static func args_for(kind: String, subject: String) -> Array:
	var catalog := PortCatalog.get_default()
	match kind:
		"harbour":
			return [catalog.get_display_name(StringName(subject))]
		"fish":
			return [FishingCatalog.get_default().get_species_name(subject).to_lower()]
		"voyage":
			var ends := subject.split("-", true, 1)
			return [catalog.get_display_name(StringName(ends[0])), catalog.get_display_name(StringName(ends[1]))] if ends.size() == 2 else []
		"weather":
			return [weather_name(int(subject.get_slice(":", 1)))]
		"sunset":
			return [subject]
	return []


## The renown key of a subject (each subject earns renown once).
static func renown_key(kind: String, subject: String) -> String:
	return "postcard:%s:%s" % [kind, subject]


## True when this subject has already earned its renown.
static func is_posted(kind: String, subject: String) -> bool:
	return GameSession.get_objective_progress().is_completed(StringName(renown_key(kind, subject)))


# --- The little game -----------------------------------------------------------------------------

static func game_title() -> String:
	return Loc.t(String(game_data().get("game_title", "Tiny Lighthouse")))


static func milestones() -> Array:
	return game_data().get("milestones", [])


static func tasks() -> Array:
	return game_data().get("tasks", [])


static func task(id: String) -> Dictionary:
	for entry: Dictionary in tasks():
		if entry.id == id:
			return entry
	return {}


## Points a whole session of `task_id` earns with `choice`: 2 for the wise
## choice, 1 otherwise.
static func session_points(task_id: String, choice: int) -> float:
	return 2.0 if choice == int(task(task_id).get("best", 0)) else 1.0


## The order the choices are shown in for session number `sessions`: rotated,
## so the wise one is not always first.
static func choice_order(task_id: String, sessions: int) -> Array[int]:
	var count := (task(task_id).get("choices", []) as Array).size()
	var order: Array[int] = []
	for i in count:
		order.append((i + sessions + task_id.length()) % maxi(count, 1))
	return order
