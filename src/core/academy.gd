class_name Academy
extends RefCounted
## The Captain's Academy (I022): the Captain's Handbook, the First Voyage and
## the contextual tips, from data/academy/academy.json. Keys are never written
## into the texts: "{interact}" and the like are filled in from the game's own
## key bindings (InputMap, as the keyboard labels them), so a text cannot name
## a wrong key. The progress lives in SettingsManager (this computer, not a
## save): a new game offers the First Voyage once; loading a game never does.

const DATA_PATH := "res://data/academy/academy.json"
const NEVER_OFFERED := ""
const ACTIVE := "active"
const SKIPPED := "skipped"
const DONE := "done"
## Keys that are not InputMap actions (handled in App by key code).
const FIXED_KEYS := {"handbook": "F1", "quicksave": "F5", "quickload": "F9", "delete_waypoint": "Delete", "anchorage_key": "M"}
const MOVE_ACTIONS: Array[StringName] = [&"move_up", &"move_left", &"move_down", &"move_right"]
const ARROWS := {"Up": "↑", "Down": "↓", "Left": "←", "Right": "→", "Escape": "Esc"}

static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_data = parsed if parsed is Dictionary else {}
		if _data.is_empty():
			push_error("Academy data %s is missing or invalid." % DATA_PATH)
	return _data


# --- Keys -------------------------------------------------------------------------------------------

## The keys bound to `action`, as the keyboard shows them ("E", "Esc"),
## joined with " / "; fixed keys (F1, F5, F9) and "move" too.
static func key(action: String) -> String:
	if FIXED_KEYS.has(action):
		return FIXED_KEYS[action]
	if action == "move":
		var letters: Array[String] = []
		var arrows: Array[String] = []
		for move in MOVE_ACTIONS:
			var labels := _labels(move)
			if labels.size() > 0:
				letters.append(labels[0])
			if labels.size() > 1:
				arrows.append(labels[1])
		return "".join(letters) + (" / " + "".join(arrows) if not arrows.is_empty() else "")
	if not InputMap.has_action(StringName(action)):
		return action
	return " / ".join(_labels(StringName(action)))


static func _labels(action: StringName) -> Array[String]:
	var out: Array[String] = []
	if not InputMap.has_action(action):
		return out
	for event in InputMap.action_get_events(action):
		var key_event := event as InputEventKey
		if key_event == null:
			continue
		var code := key_event.keycode
		if key_event.physical_keycode != KEY_NONE and DisplayServer.get_name() != "headless":
			code = DisplayServer.keyboard_get_keycode_from_physical(key_event.physical_keycode)
		if code == KEY_NONE:
			code = key_event.physical_keycode
		var label := OS.get_keycode_string(code)
		label = String(ARROWS.get(label, label))
		if not label.is_empty() and not out.has(label):
			out.append(label)
	return out


## `text` in the current language with every {action} filled in.
static func fill(text: String) -> String:
	var out := Loc.t(text)
	var start := out.find("{")
	while start >= 0:
		var end := out.find("}", start)
		if end < 0:
			break
		var name := out.substr(start + 1, end - start - 1)
		var label := key(name)
		out = out.substr(0, start) + label + out.substr(end + 1)
		start = out.find("{", start + label.length())
	return out


# --- The Handbook -----------------------------------------------------------------------------------

static func categories() -> Array:
	return data().get("categories", [])


static func pages() -> Array:
	return data().get("pages", [])


static func page(id: String) -> Dictionary:
	for entry: Dictionary in pages():
		if entry.id == id:
			return entry
	return {}


static func category_title(id: String) -> String:
	for entry: Dictionary in categories():
		if entry.id == id:
			return Loc.t(String(entry.title))
	return id


## The pages whose title or text (in the current language, keys filled in)
## contain every word of `query`, in Handbook order; all pages for "".
static func search(query: String) -> Array[String]:
	var words := query.to_lower().split(" ", false)
	var found: Array[String] = []
	for entry: Dictionary in pages():
		var haystack := (Loc.t(String(entry.title)) + " " + fill(String(entry.text)) + " " + category_title(String(entry.category))).to_lower()
		if Array(words).all(func(word: String) -> bool: return haystack.contains(word)):
			found.append(String(entry.id))
	return found


# --- The First Voyage ---------------------------------------------------------------------------------

static func steps() -> Array:
	return data().get("first_voyage", [])


static func first_voyage_state() -> String:
	return String(SettingsManager.get_academy().first_voyage)


static func current_step() -> int:
	return int(SettingsManager.get_academy().step)


static func _set_progress(key_name: String, value: Variant) -> void:
	var progress := SettingsManager.get_academy()
	progress[key_name] = value
	SettingsManager.set_academy(progress)


## Begins (or begins again) the First Voyage at its first step.
static func begin_first_voyage() -> void:
	var progress := SettingsManager.get_academy()
	progress.first_voyage = ACTIVE
	progress.step = 0
	SettingsManager.set_academy(progress)


static func skip_first_voyage() -> void:
	_set_progress("first_voyage", SKIPPED)


## The current step is done: on to the next, or the voyage is done.
static func complete_step() -> void:
	var progress := SettingsManager.get_academy()
	progress.step = int(progress.step) + 1
	if int(progress.step) >= steps().size():
		progress.first_voyage = DONE
	SettingsManager.set_academy(progress)


# --- Tips ---------------------------------------------------------------------------------------------

static func tip(id: String) -> Dictionary:
	return (data().get("tips", {}) as Dictionary).get(id, {})


static func is_tip_seen(id: String) -> bool:
	return (SettingsManager.get_academy().seen as Array).has(id)


static func mark_tip_seen(id: String) -> void:
	var progress := SettingsManager.get_academy()
	if not (progress.seen as Array).has(id):
		progress.seen.append(id)
		SettingsManager.set_academy(progress)


## Forgets the tips shown, so they come again (Settings or the Handbook).
static func reset_tips() -> void:
	_set_progress("seen", [])
