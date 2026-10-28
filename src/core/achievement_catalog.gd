class_name AchievementCatalog
extends RefCounted
## The achievement collection (I024, The Company We Keep), from
## data/progression/achievements.json: a smaller set of meaningful
## achievements in a few categories, shown on the cabin laptop.
##
## An achievement is a view on the renown records the game already keeps
## (ObjectiveProgress.completed), never a second account: it is unlocked when
## one of its records is completed (or `count` records with its `prefix`, or
## any generated far-harbour objective), and renown is paid by those records
## exactly once, as it always was. So nothing is paid twice, and an older
## save's earned records show as unlocked achievements at once.
##
## When and where: the record's own first time (always kept), and since I024
## the harbour or position and the boat ("at"). Older records have no place:
## "Location not recorded" - nothing is made up. A record that only exists as
## a total (renown passed before I024, publishing) shows "Previously unlocked".

const DEFAULT_PATH := "res://data/progression/achievements.json"
const ICON_DIR := "res://assets/achievements/"
const SECRET_ICON := "secret"

static var _default: AchievementCatalog

## {"id", "title"} in display order.
var categories: Array[Dictionary] = []
## {"id", "category", "icon", "title", "text", "hint", "records", "prefix",
## "count", "generated", "renown", "reward", "secret"} in display order.
var achievements: Array[Dictionary] = []
var _by_id := {}


static func get_default() -> AchievementCatalog:
	if _default == null:
		_default = load_from(DEFAULT_PATH)
	return _default


static func clear_default() -> void:
	_default = null


static func load_from(path: String) -> AchievementCatalog:
	var catalog := AchievementCatalog.new()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		push_error("Cannot read achievements from %s" % path)
		return catalog
	var known := {}
	for entry: Variant in data.get("categories", []):
		if entry is Dictionary and entry.get("id") is String:
			catalog.categories.append({"id": String(entry.id), "title": str(entry.get("title", entry.id))})
			known[String(entry.id)] = true
	for entry: Variant in data.get("achievements", []):
		var problem := _validate(entry, known)
		if problem == "" and catalog._by_id.has(String(entry.id)):
			problem = "duplicate id"
		if problem != "":
			push_error("Achievement '%s' left out: %s" % [entry.get("id", "?") if entry is Dictionary else "?", problem])
			continue
		var records: Array[String] = []
		for r: Variant in entry.get("records", []):
			records.append(str(r))
		var achievement := {
			"id": String(entry.id), "category": String(entry.category), "icon": str(entry.get("icon", entry.id)),
			"title": str(entry.get("title", entry.id)), "text": str(entry.get("text", "")), "hint": str(entry.get("hint", "")),
			"records": records, "prefix": str(entry.get("prefix", "")), "count": int(entry.get("count", 1)),
			"generated": bool(entry.get("generated", false)), "renown": int(entry.get("renown", 0)),
			"reward": int(entry.get("reward", 0)), "secret": bool(entry.get("secret", false)),
		}
		catalog.achievements.append(achievement)
		catalog._by_id[achievement.id] = achievement
	return catalog


static func _validate(entry: Variant, categories: Dictionary) -> String:
	if not entry is Dictionary or not entry.get("id") is String or String(entry.id).is_empty():
		return "missing id"
	if not categories.has(str(entry.get("category", ""))):
		return "unknown category '%s'" % entry.get("category")
	var has_rule: bool = not (entry.get("records", []) as Array).is_empty() or str(entry.get("prefix", "")) != "" or bool(entry.get("generated", false))
	return "" if has_rule else "no unlock rule (records, prefix or generated)"


func get_achievement(id: String) -> Dictionary:
	return _by_id.get(id, {})


## Categories that hold at least one achievement (no empty ones), in order.
func get_categories() -> Array[Dictionary]:
	var used := {}
	for a in achievements:
		used[a.category] = true
	return categories.filter(func(c: Dictionary) -> bool: return used.has(c.id))


func get_category_title(id: String) -> String:
	for c in categories:
		if c.id == id:
			return Loc.t(c.title)
	return id


## The unlock of `achievement` in `progress` (an ObjectiveProgress):
## {} when locked; else {"time": game time or -1 (not recorded), "at": {} or
## {"port", "lon", "lat", "vessel"}, "record": the record id, "reward"}.
func unlock_of(achievement: Dictionary, progress: ObjectiveProgress) -> Dictionary:
	var found: Array[Dictionary] = []
	var objectives := ObjectiveCatalog.get_default()
	for id: String in progress.completed:
		var matches := false
		if achievement.records.has(id):
			matches = true
		elif achievement.prefix != "" and id.begins_with(achievement.prefix):
			matches = true
		elif achievement.generated and objectives.has_objective(StringName(id)) and bool(objectives.get_objective(StringName(id)).generated):
			matches = true
		if matches:
			var entry: Dictionary = progress.completed[id]
			found.append({"record": id, "time": float(entry.first), "at": entry.get("at", {}), "reward": int(entry.get("r", achievement.reward))})
	var needed := maxi(achievement.count, 1) if achievement.prefix != "" else 1
	if found.size() >= needed:
		found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time < b.time)
		return found[needed - 1]  # the moment it was reached
	# Passed before the record existed (I024): unlocked, without a date.
	if achievement.renown > 0 and progress.lifetime_renown >= achievement.renown:
		return {"record": "", "time": -1.0, "at": {}, "reward": achievement.reward}
	if achievement.records.has("publish:first") and progress.publications > 0:
		return {"record": "", "time": -1.0, "at": {}, "reward": achievement.reward}
	return {}


## Every achievement with its state, for the collection: [{"achievement",
## "unlock" ({} when locked)}], unlocked first (most recent first; undated
## ones after the dated), then the locked ones in catalogue order. Only
## those in `category` ("" = all).
func collection(progress: ObjectiveProgress, category := "") -> Array[Dictionary]:
	var unlocked: Array[Dictionary] = []
	var locked: Array[Dictionary] = []
	for achievement in achievements:
		if category != "" and achievement.category != category:
			continue
		var unlock := unlock_of(achievement, progress)
		(unlocked if not unlock.is_empty() else locked).append({"achievement": achievement, "unlock": unlock})
	unlocked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.unlock.time) > float(b.unlock.time))
	return unlocked + locked


## Unlocked and total counts.
func count_unlocked(progress: ObjectiveProgress) -> Vector2i:
	var done := 0
	for achievement in achievements:
		if not unlock_of(achievement, progress).is_empty():
			done += 1
	return Vector2i(done, achievements.size())


## The badge picture of an achievement (the secret one while a secret is
## still hidden), or null when it is missing.
static func icon_of(achievement: Dictionary, unlocked: bool) -> Texture2D:
	var icon := SECRET_ICON if achievement.secret and not unlocked else String(achievement.icon)
	var path := ICON_DIR + icon + ".png"
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## The title shown: a hidden secret shows only "Secret achievement".
static func shown_title(achievement: Dictionary, unlocked: bool) -> String:
	return Loc.t("Secret achievement") if achievement.secret and not unlocked else Loc.t(achievement.title)


## The text shown: a hidden secret shows its hint.
static func shown_text(achievement: Dictionary, unlocked: bool) -> String:
	if achievement.secret and not unlocked:
		return Loc.t(achievement.hint) if achievement.hint != "" else Loc.t("Not described: you will know it when you find it.")
	return Loc.t(achievement.text)


## When it was unlocked, for the detail ("Previously unlocked" when the
## save does not know).
static func describe_when(unlock: Dictionary) -> String:
	if float(unlock.get("time", -1.0)) < 0.0:
		return Loc.t("Previously unlocked")
	return Simulation.format_game_time(float(unlock.time), false)


## Where it was unlocked: the harbour, or the position at sea, or "Location
## not recorded". Never more precise than the game knows (about a mile).
static func describe_where(unlock: Dictionary) -> String:
	var at: Dictionary = unlock.get("at", {})
	if at.is_empty():
		return Loc.t("Location not recorded")
	var port := PortCatalog.get_default().get_port(StringName(str(at.get("port", ""))))
	if port:
		return Loc.t("In %s, %s") % [port.display_name, port.country] if port.country != "" else Loc.t("In %s") % port.display_name
	return Loc.t("At sea, %s") % format_position(Vector2(float(at.lon), float(at.lat)))


## "55.2°N 11.4°E"
static func format_position(geo: Vector2) -> String:
	return "%.1f°%s %.1f°%s" % [absf(geo.y), "N" if geo.y >= 0.0 else "S", absf(geo.x), "E" if geo.x >= 0.0 else "W"]


## The boat it was earned on ("" when not recorded).
static func describe_boat(unlock: Dictionary) -> String:
	var vessel := VesselCatalog.get_default().get_vessel(StringName(str((unlock.get("at", {}) as Dictionary).get("vessel", ""))))
	return vessel.display_name if vessel else ""
